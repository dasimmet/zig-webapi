"use strict";
import { Zjb } from "./zjb_bindings.js";

const zjb = new Zjb();
window.zjb = zjb;

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
    results = await WebAssembly.instantiateStreaming(fetch("example.wasm"), imports);
  } catch (err) {
    console.warn("instantiateStreaming failed, falling back to arrayBuffer:", err);
    const response = await fetch("example.wasm");
    if (!response.ok) {
      throw new Error(`Failed to load example.wasm: ${response.status} ${response.statusText}`);
    }
    results = await WebAssembly.instantiate(await response.arrayBuffer(), imports);
  }

  zjb.setInstance(results.instance);
  if (results.instance.exports._start) {
    results.instance.exports._start();
  } else if (results.instance.exports.main) {
    results.instance.exports.main();
  }
}

function launch() {
  start().catch((error) => console.error("Could not start the WebAPI example:", error));
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", launch);
} else {
  launch();
}
