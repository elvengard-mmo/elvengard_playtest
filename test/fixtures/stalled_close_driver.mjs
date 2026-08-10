import readline from "node:readline"

const lines = readline.createInterface({input: process.stdin})

lines.on("line", line => {
  const request = JSON.parse(line)

  if (request.method !== "browser.close") {
    process.stdout.write(`${JSON.stringify({id: request.id, result: true})}\n`)
  }
})

process.stdout.write(`${JSON.stringify({event: "driver.ready", params: {protocol: 1}})}\n`)
