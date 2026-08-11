const {spawn} = require("node:child_process")

function launchBrowserProcess() {
  return spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], {stdio: "ignore"})
}

function browserServer(browserProcess) {
  return {
    close() {
      return new Promise(() => {})
    },

    kill() {
      return new Promise(resolve => {
        browserProcess.once("exit", resolve)
        browserProcess.kill("SIGKILL")
      })
    },

    process() {
      return browserProcess
    },

    wsEndpoint() {
      return "ws://playtest.invalid"
    },
  }
}

const chromium = {
  async launchServer() {
    return browserServer(launchBrowserProcess())
  },

  async connect() {
    return {
      async newContext() {
        throw new Error("Fake Playwright contexts are not implemented")
      },
    }
  },
}

module.exports = {chromium}
