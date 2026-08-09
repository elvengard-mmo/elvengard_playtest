import readline from "node:readline"

const protocolVersion = 1
const lines = readline.createInterface({input: process.stdin})

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`)
}

write({event: "driver.ready", params: {protocol: protocolVersion}})

lines.on("line", line => {
  const request = JSON.parse(line)

  switch (request.method) {
    case "echo":
      write({id: request.id, result: request.params})
      break

    case "emit":
      write({event: "fixture.event", params: request.params})
      write({id: request.id, result: true})
      break

    default:
      write({
        id: request.id,
        error: {code: "unknown_method", message: `Unknown method: ${request.method}`},
      })
  }
})
