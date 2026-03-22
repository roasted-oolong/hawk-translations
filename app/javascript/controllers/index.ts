// controllers/index.ts
// Register all Stimulus controllers here.
//
// Naming convention: filename `foo_bar_controller.ts` → identifier "foo-bar"

import { application } from "./application"

import FlashController from "./flash_controller"
application.register("flash", FlashController)

import PollController from "./poll_controller"
application.register("poll", PollController)
