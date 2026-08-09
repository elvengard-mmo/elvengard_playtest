(() => {
  if (window.__gameTest) return

  const protocol = 1
  let adapter = null
  let frame = 0
  let frameWaiters = []

  function trackFrame() {
    frame += 1

    const ready = frameWaiters.filter(waiter => frame >= waiter.target)
    frameWaiters = frameWaiters.filter(waiter => frame < waiter.target)
    ready.forEach(waiter => waiter.resolve(frame))

    window.requestAnimationFrame(trackFrame)
  }

  window.requestAnimationFrame(trackFrame)

  const probe = {
    protocol,

    register(nextAdapter) {
      if (!nextAdapter || typeof nextAdapter !== "object") {
        throw new TypeError("Playtest probe adapters must be objects")
      }

      adapter = nextAdapter
      return true
    },

    ready() {
      return adapter !== null
    },

    frame() {
      return frame
    },

    call(method, ...args) {
      if (!adapter) throw new Error("No Playtest game adapter has been registered")

      const operation = adapter[method]
      if (typeof operation !== "function") {
        throw new Error(`Unknown Playtest probe operation: ${method}`)
      }

      return operation(...args)
    },

    waitForFrames(count) {
      if (!Number.isInteger(count) || count < 1) {
        throw new TypeError("Playtest frame waits require a positive integer")
      }

      return new Promise(resolve => {
        frameWaiters.push({target: frame + count, resolve})
      })
    },
  }

  Object.defineProperty(window, "__gameTest", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze(probe),
  })
})()
