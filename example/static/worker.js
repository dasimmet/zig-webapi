"use strict";
globalThis.window = globalThis;
import { Zjb } from "./worker_zjb.js";

const zjb = new Zjb();
const pendingMessages = [];
let ready = false;

self.addEventListener("message", (ev) => {
  if (!ready) {
    pendingMessages.push(ev.data);
  }
});

async function start() {
  const imports = {
    env: {
      memory: new WebAssembly.Memory({ initial: 16 }),
      __stack_pointer: 0,
    },
    zjb: zjb.imports,
  };

  let results;
  try {
    results = await WebAssembly.instantiateStreaming(fetch("worker.wasm"), imports);
  } catch (err) {
    console.warn("worker instantiateStreaming failed, falling back to arrayBuffer:", err);
    const response = await fetch("worker.wasm");
    if (!response.ok) {
      throw new Error(`Failed to load worker.wasm: ${response.status} ${response.statusText}`);
    }
    results = await WebAssembly.instantiate(await response.arrayBuffer(), imports);
  }

  zjb.setInstance(results.instance);
  if (results.instance.exports._start) {
    results.instance.exports._start();
  } else if (results.instance.exports.main) {
    results.instance.exports.main();
  }

  ready = true;
  for (const data of pendingMessages) {
    self.dispatchEvent(new MessageEvent("message", { data }));
  }
  pendingMessages.length = 0;
}

start();
