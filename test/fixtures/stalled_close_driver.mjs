import readline from "node:readline"

const lines = readline.createInterface({input: process.stdin})

process.stdout.on("error", error => {
  if (error.code === "EPIPE") process.exit(0)
  throw error
})

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`)
}

lines.on("line", line => {
  const request = JSON.parse(line)

  if (request.method === "driver.close") {
    write({event: "driver.close_requested", params: {}})
    setTimeout(() => write({id: request.id, result: true}), 100)
  } else if (request.method === "browser.close") {
    write({event: "browser.close_requested", params: {}})
  } else {
    write({id: request.id, result: true})
  }
})

write({event: "driver.ready", params: {protocol: 1, pid: process.pid}})
