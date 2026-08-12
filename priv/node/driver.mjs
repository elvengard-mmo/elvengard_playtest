import {createRequire} from "node:module"
import {writeFile} from "node:fs/promises"
import readline from "node:readline"

const protocolVersion = 1
const require = createRequire(import.meta.url)

process.stdout.on("error", error => {
  if (error.code === "EPIPE") process.exit(0)
  throw error
})

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`)
}

function serializeError(error) {
  return {
    code: error?.name || "driver_error",
    message: error?.message || String(error),
    stack: error?.stack || null,
  }
}

function loadPlaywright() {
  const configuredPath = process.env.PLAYTEST_PLAYWRIGHT_PATH
  return configuredPath ? require(configuredPath) : require("playwright")
}

let playwright

try {
  playwright = loadPlaywright()
} catch (error) {
  write({
    event: "driver.fatal",
    params: {
      code: "playwright_not_found",
      message: error.message,
      operation: "load_playwright",
    },
  })
  process.exit(1)
}

const browsers = new Map()
const contexts = new Map()
const pages = new Map()
const videos = new Map()
const canvasRecordings = new Map()
let sequence = 0

function nextId(prefix) {
  sequence += 1
  return `${prefix}-${sequence}`
}

function fetchObject(collection, id, type) {
  const value = collection.get(id)
  if (!value) throw new Error(`Unknown ${type}: ${id}`)
  return value
}

function pageFor(params) {
  return fetchObject(pages, params.page_id, "page")
}

function attachPageEvents(page, pageId) {
  page.on("console", message => {
    write({
      event: "page.console",
      params: {page_id: pageId, level: message.type(), text: message.text()},
    })
  })

  page.on("pageerror", error => {
    write({event: "page.error", params: {page_id: pageId, ...serializeError(error)}})
  })

  page.on("crash", () => {
    write({event: "page.crash", params: {page_id: pageId}})
  })

  page.on("websocket", socket => {
    const socketId = nextId("websocket")
    const emitFrame = direction => payload => {
      const binary = Buffer.isBuffer(payload)
      write({
        event: `websocket.frame_${direction}`,
        params: {
          page_id: pageId,
          socket_id: socketId,
          url: socket.url(),
          binary,
          payload: binary ? payload.toString("base64") : payload,
        },
      })
    }

    write({
      event: "websocket.open",
      params: {page_id: pageId, socket_id: socketId, url: socket.url()},
    })
    socket.on("framesent", emitFrame("sent"))
    socket.on("framereceived", emitFrame("received"))
    socket.on("socketerror", error => {
      write({
        event: "websocket.error",
        params: {page_id: pageId, socket_id: socketId, message: String(error)},
      })
    })
    socket.on("close", () => {
      write({event: "websocket.close", params: {page_id: pageId, socket_id: socketId}})
    })
  })
}

const handlers = {
  async "driver.close"() {
    await closeAllBrowsers()
    return true
  },

  async "browser.launch"(params) {
    const browserType = playwright[params.browser || "chromium"]
    if (!browserType) throw new Error(`Unknown browser engine: ${params.browser}`)

    const server = await browserType.launchServer({
      headless: params.headless ?? true,
      executablePath: params.executable_path,
      args: params.args || [],
    })
    let browser

    try {
      browser = await browserType.connect(server.wsEndpoint())
    } catch (error) {
      await server.kill()
      throw error
    }

    const browserId = nextId("browser")
    browsers.set(browserId, {browser, server})
    return {browser_id: browserId, browser_pid: server.process().pid}
  },

  async "browser.close"(params) {
    const session = fetchObject(browsers, params.browser_id, "browser")
    await closeBrowserSession(session, params.timeout)
    browsers.delete(params.browser_id)
    return true
  },

  async "context.new"(params) {
    const {browser} = fetchObject(browsers, params.browser_id, "browser")
    const context = await browser.newContext({
      viewport: params.viewport,
      userAgent: params.user_agent,
      ignoreHTTPSErrors: params.ignore_https_errors,
      recordVideo: params.record_video_dir
        ? {dir: params.record_video_dir, size: params.record_video_size}
        : undefined,
    })
    const contextId = nextId("context")
    contexts.set(contextId, context)
    return {context_id: contextId}
  },

  async "context.close"(params) {
    const context = fetchObject(contexts, params.context_id, "context")
    await context.close()
    contexts.delete(params.context_id)
    return true
  },

  async "context.add_init_script"(params) {
    const context = fetchObject(contexts, params.context_id, "context")
    await context.addInitScript({content: params.source})
    return true
  },

  async "context.tracing_start"(params) {
    const context = fetchObject(contexts, params.context_id, "context")
    await context.tracing.start({
      screenshots: params.screenshots ?? true,
      snapshots: params.snapshots ?? true,
      sources: params.sources ?? true,
    })
    return true
  },

  async "context.tracing_stop"(params) {
    const context = fetchObject(contexts, params.context_id, "context")
    await context.tracing.stop({path: params.path})
    return params.path
  },

  async "page.new"(params) {
    const context = fetchObject(contexts, params.context_id, "context")
    const page = await context.newPage()
    const pageId = nextId("page")
    pages.set(pageId, page)
    attachPageEvents(page, pageId)
    return {page_id: pageId}
  },

  async "page.goto"(params) {
    const page = pageFor(params)
    const response = await page.goto(params.url, {
      waitUntil: params.wait_until || "load",
      timeout: params.timeout,
    })
    return {status: response?.status() ?? null, url: page.url()}
  },

  async "page.click"(params) {
    const page = pageFor(params)
    await page.locator(params.selector).click({
      button: params.button,
      clickCount: params.click_count,
      delay: params.delay,
      force: params.force,
      position: params.position,
      timeout: params.timeout,
    })
    return true
  },

  async "page.fill"(params) {
    const locator = pageFor(params).locator(params.selector)
    await locator.fill("")
    await locator.pressSequentially(params.value, {delay: params.delay})
    return true
  },

  async "page.paste"(params) {
    const page = pageFor(params)
    const locator = page.locator(params.selector)
    await locator.focus()
    await locator.fill(params.value)
    await page.waitForTimeout(params.delay)
    return true
  },

  async "locator.visible"(params) {
    return pageFor(params).locator(params.selector).isVisible()
  },

  async "locator.text"(params) {
    return pageFor(params).locator(params.selector).textContent()
  },

  async "locator.attribute"(params) {
    return pageFor(params).locator(params.selector).getAttribute(params.name)
  },

  async "locator.count"(params) {
    return pageFor(params).locator(params.selector).count()
  },

  async "locator.wait_for"(params) {
    await pageFor(params).locator(params.selector).waitFor({
      state: params.state,
      timeout: params.timeout,
    })
    return true
  },

  async "page.evaluate"(params) {
    const result = await pageFor(params).evaluate(
      async ({expression, argument}) => {
        const evaluated = globalThis.eval(expression)
        return typeof evaluated === "function" ? await evaluated(argument) : evaluated
      },
      {expression: params.expression, argument: params.argument},
    )
    return result === undefined ? null : result
  },

  async "page.wait_for"(params) {
    await pageFor(params).waitForFunction(params.expression, params.argument, {
      timeout: params.timeout,
      polling: params.polling,
    })
    return true
  },

  async "page.resize"(params) {
    await pageFor(params).setViewportSize({width: params.width, height: params.height})
    return true
  },

  async "page.screenshot"(params) {
    await pageFor(params).screenshot({
      path: params.path,
      fullPage: params.full_page,
      animations: params.animations,
    })
    return params.path
  },

  async "page.video"(params) {
    const video = pageFor(params).video()
    if (!video) return null

    const videoId = nextId("video")
    videos.set(videoId, {type: "playwright", video})
    return {video_id: videoId}
  },

  async "canvas_video.start"(params) {
    const page = pageFor(params)
    const recordingId = nextId("canvas-recording")
    const metadata = await page.evaluate(
      ({recordingId, selector, fps, mimeType, videoBitsPerSecond}) => {
        const canvas = document.querySelector(selector)
        if (!(canvas instanceof HTMLCanvasElement)) {
          throw new Error(`Canvas video selector did not match a canvas: ${selector}`)
        }
        if (typeof canvas.captureStream !== "function" || typeof MediaRecorder === "undefined") {
          throw new Error("Canvas video recording is not supported by this browser")
        }

        const candidates = mimeType
          ? [mimeType]
          : ["video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"]
        const selectedMimeType = candidates.find(candidate => MediaRecorder.isTypeSupported(candidate))
        if (!selectedMimeType) {
          throw new Error(`Canvas video MIME type is not supported: ${mimeType || "video/webm"}`)
        }

        const stream = canvas.captureStream(fps)
        const recorder = new MediaRecorder(stream, {
          mimeType: selectedMimeType,
          videoBitsPerSecond,
        })
        const chunks = []
        let resolveStopped
        let rejectStopped
        const stopped = new Promise((resolve, reject) => {
          resolveStopped = resolve
          rejectStopped = reject
        })

        recorder.addEventListener("dataavailable", event => {
          if (event.data.size > 0) chunks.push(event.data)
        })
        recorder.addEventListener("error", event => rejectStopped(event.error))
        recorder.addEventListener("stop", () => {
          const blob = new Blob(chunks, {type: recorder.mimeType || selectedMimeType})
          const reader = new FileReader()
          reader.addEventListener("error", () => rejectStopped(reader.error))
          reader.addEventListener("loadend", () => {
            const [, base64] = String(reader.result).split(",", 2)
            resolveStopped({base64, mime_type: blob.type, size: blob.size})
          })
          reader.readAsDataURL(blob)
        })

        globalThis.__elvengardCanvasVideos ||= new Map()
        globalThis.__elvengardCanvasVideos.set(recordingId, {recorder, stopped, stream})
        recorder.start(100)

        return {
          mime_type: recorder.mimeType || selectedMimeType,
          width: canvas.width,
          height: canvas.height,
          fps,
        }
      },
      {
        recordingId,
        selector: params.selector,
        fps: params.fps || 30,
        mimeType: params.mime_type,
        videoBitsPerSecond: params.video_bits_per_second,
      },
    )

    canvasRecordings.set(recordingId, {pageId: params.page_id})
    return {recording_id: recordingId, ...metadata}
  },

  async "canvas_video.stop"(params) {
    const recording = fetchObject(canvasRecordings, params.recording_id, "canvas recording")
    const page = fetchObject(pages, recording.pageId, "page")
    const artifact = await page.evaluate(async recordingId => {
      const recordings = globalThis.__elvengardCanvasVideos
      const active = recordings?.get(recordingId)
      if (!active) throw new Error(`Unknown canvas recording: ${recordingId}`)

      if (active.recorder.state !== "inactive") active.recorder.stop()
      const result = await active.stopped
      active.stream.getTracks().forEach(track => track.stop())
      recordings.delete(recordingId)
      return result
    }, params.recording_id)

    canvasRecordings.delete(params.recording_id)
    const videoId = nextId("video")
    videos.set(videoId, {
      type: "buffer",
      buffer: Buffer.from(artifact.base64, "base64"),
    })
    return {video_id: videoId, mime_type: artifact.mime_type, size: artifact.size}
  },

  async "canvas_video.cancel"(params) {
    const recording = fetchObject(canvasRecordings, params.recording_id, "canvas recording")
    const page = fetchObject(pages, recording.pageId, "page")
    await page.evaluate(async recordingId => {
      const recordings = globalThis.__elvengardCanvasVideos
      const active = recordings?.get(recordingId)
      if (!active) return

      if (active.recorder.state !== "inactive") active.recorder.stop()
      await active.stopped
      active.stream.getTracks().forEach(track => track.stop())
      recordings.delete(recordingId)
    }, params.recording_id)
    canvasRecordings.delete(params.recording_id)
    return true
  },

  async "page.close"(params) {
    const page = pageFor(params)
    await page.close()
    pages.delete(params.page_id)
    return true
  },

  async "video.save_as"(params) {
    const artifact = fetchObject(videos, params.video_id, "video")
    if (artifact.type === "playwright") {
      await artifact.video.saveAs(params.path)
    } else {
      await writeFile(params.path, artifact.buffer)
    }
    return params.path
  },

  async "video.delete"(params) {
    const artifact = fetchObject(videos, params.video_id, "video")
    if (artifact.type === "playwright") await artifact.video.delete()
    videos.delete(params.video_id)
    return true
  },

  async "keyboard.down"(params) {
    await pageFor(params).keyboard.down(params.key)
    return true
  },

  async "keyboard.up"(params) {
    await pageFor(params).keyboard.up(params.key)
    return true
  },

  async "keyboard.press"(params) {
    await pageFor(params).keyboard.press(params.key, {delay: params.delay})
    return true
  },

  async "keyboard.press_when"(params) {
    const page = pageFor(params)
    await page.waitForFunction(params.expression, params.argument, {
      timeout: params.timeout,
      polling: params.polling,
    })
    await page.keyboard.press(params.key, {delay: params.delay})
    return true
  },

  async "keyboard.hold_for"(params) {
    const page = pageFor(params)
    await page.keyboard.down(params.key)

    try {
      await page.waitForTimeout(params.duration_ms)
    } finally {
      await page.keyboard.up(params.key)
    }

    return true
  },

  async "keyboard.hold_until"(params) {
    const page = pageFor(params)
    const startedAt = performance.now()
    await page.keyboard.down(params.key)

    try {
      await page.waitForFunction(params.expression, params.argument, {
        timeout: params.timeout,
        polling: params.polling,
      })
      const remaining = params.minimum_duration_ms - (performance.now() - startedAt)
      if (remaining > 0) await page.waitForTimeout(remaining)
    } finally {
      await page.keyboard.up(params.key)
    }

    return true
  },

  async "mouse.move"(params) {
    const page = pageFor(params)
    await page.mouse.move(params.x, params.y, {steps: params.steps})
    await page.waitForTimeout(params.delay)
    return true
  },

  async "mouse.down"(params) {
    await pageFor(params).mouse.down({button: params.button, clickCount: params.click_count})
    return true
  },

  async "mouse.click"(params) {
    const page = pageFor(params)
    const input = {button: params.button, clickCount: params.click_count}
    await page.mouse.down(input)

    try {
      await page.waitForTimeout(params.delay)
    } finally {
      await page.mouse.up(input)
    }

    return true
  },

  async "mouse.hold_until"(params) {
    const page = pageFor(params)
    const input = {button: params.button, clickCount: params.click_count}
    const startedAt = performance.now()
    await page.mouse.down(input)

    try {
      await page.waitForFunction(params.expression, params.argument, {
        timeout: params.timeout,
        polling: params.polling,
      })
      const remaining = params.minimum_duration_ms - (performance.now() - startedAt)
      if (remaining > 0) await page.waitForTimeout(remaining)
    } finally {
      await page.mouse.up(input)
    }

    return true
  },

  async "mouse.hold_for"(params) {
    const page = pageFor(params)
    const input = {button: params.button, clickCount: params.click_count}
    await page.mouse.down(input)

    try {
      await page.waitForTimeout(params.duration_ms)
    } finally {
      await page.mouse.up(input)
    }

    return true
  },

  async "mouse.up"(params) {
    await pageFor(params).mouse.up({button: params.button, clickCount: params.click_count})
    return true
  },
}

async function closeBrowserSession({server}, timeout = 4_000) {
  let timer

  try {
    await Promise.race([
      server.close(),
      new Promise((_, reject) => {
        timer = setTimeout(() => {
          reject(Object.assign(new Error(`Browser close exceeded ${timeout}ms`), {name: "timeout"}))
        }, timeout)
      }),
    ])
  } catch (error) {
    write({
      event: "browser.close_forced",
      params: {browser_pid: server.process().pid, cause: serializeError(error)},
    })

    const browserProcess = server.process()
    if (browserProcess.exitCode === null && browserProcess.signalCode === null) {
      await server.kill()
    }
  } finally {
    clearTimeout(timer)
  }
}

async function closeAllBrowsers() {
  await Promise.allSettled([...browsers.values()].map(session => closeBrowserSession(session)))
  browsers.clear()
  contexts.clear()
  pages.clear()
  videos.clear()
  canvasRecordings.clear()
}

const lines = readline.createInterface({input: process.stdin})

lines.on("line", async line => {
  let request

  try {
    request = JSON.parse(line)
    const handler = handlers[request.method]
    if (!handler) {
      throw Object.assign(new Error(`Unknown Playtest driver method: ${request.method}`), {
        name: "unknown_method",
      })
    }

    const result = await handler(request.params || {})
    write({id: request.id, result: result === undefined ? null : result})
  } catch (error) {
    write({id: request?.id ?? null, error: serializeError(error)})
  }
})

lines.on("close", async () => {
  await closeAllBrowsers()
  process.exit(0)
})

process.on("SIGTERM", async () => {
  await closeAllBrowsers()
  process.exit(0)
})

write({event: "driver.ready", params: {protocol: protocolVersion}})
