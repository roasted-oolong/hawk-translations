// Register Stimulus controllers here.
// With esbuild (no importmap), controllers are imported explicitly rather
// than using eagerLoadControllersFrom. Add each controller as:
//
//   import HelloController from "./hello_controller"
//   application.register("hello", HelloController)
//
// No controllers exist yet — they will be added starting at M14.

import { application } from "./application"

export { application }
