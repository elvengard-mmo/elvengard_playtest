import {createRequire} from "node:module"
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
  async "browser.launch"(params) {
    const browserType = playwright[params.browser || "chromium"]
    if (!browserType) throw new Error(`Unknown browser engine: ${params.browser}`)

    const browser = await browserType.launch({
      headless: params.headless ?? true,
      executablePath: params.executable_path,
      args: params.args || [],
    })
    const browserId = nextId("browser")
    browsers.set(browserId, browser)
    return {browser_id: browserId}
  },

  async "browser.close"(params) {
    const browser = fetchObject(browsers, params.browser_id, "browser")
    await browser.close()
    browsers.delete(params.browser_id)
    return true
  },

  async "context.new"(params) {
    const browser = fetchObject(browsers, params.browser_id, "browser")
    const context = await browser.newContext({
      viewport: params.viewport,
      userAgent: params.user_agent,
      ignoreHTTPSErrors: params.ignore_https_errors,
      recordVideo: params.record_video_dir ? {dir: params.record_video_dir} : undefined,
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
      force: params.force,
      position: params.position,
      timeout: params.timeout,
    })
    return true
  },

  async "page.fill"(params) {
    await pageFor(params).locator(params.selector).fill(params.value)
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

  async "page.close"(params) {
    const page = pageFor(params)
    await page.close()
    pages.delete(params.page_id)
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

  async "mouse.move"(params) {
    await pageFor(params).mouse.move(params.x, params.y, {steps: params.steps})
    return true
  },

  async "mouse.down"(params) {
    await pageFor(params).mouse.down({button: params.button, clickCount: params.click_count})
    return true
  },

  async "mouse.up"(params) {
    await pageFor(params).mouse.up({button: params.button, clickCount: params.click_count})
    return true
  },
}

async function closeAllBrowsers() {
  await Promise.allSettled([...browsers.values()].map(browser => browser.close()))
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
