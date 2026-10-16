// Web build smoke test in headless Chromium with phone emulation + real touch events.
//
//   tools/export/export_web.sh && node tools/export/web_smoke.mjs [--out dir] [--device "Pixel 7"]
//
// Serves build/web (tools/export/serve_web.py), opens it as a landscape phone (touch,
// isMobile, DPR), and walks the real flow BY TAP ONLY: main menu -> ENTER THE WORLD ->
// element select (tap a card, tap BEGIN) -> world loading -> arrival skip -> gameplay with
// the touch overlay (stick push, look drag, Strike taps through CDP multi-touch).
// Screenshots go to --out; console errors are collected and printed. Exit code 1 when the
// page fails to boot or Godot reports script errors.
//
// Positions are given in the game's 1920x1080 design space and converted to CSS pixels
// with the canvas_items / expand stretch (scale = viewport height / 1080 on wide phones).
// Needs Playwright (NODE_PATH=/opt/node-tools/node_modules in the dev container; CI installs it).

import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium, devices } = require("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const args = process.argv.slice(2);
const opt = (name, def) => {
	const i = args.indexOf("--" + name);
	return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
};
const outDir = path.resolve(opt("out", path.join(root, ".playtest", "web")));
const deviceName = opt("device", "Pixel 7");
const port = parseInt(opt("port", "8061"), 10);
const bootTimeout = parseInt(opt("boot-timeout", "240"), 10) * 1000;
const steps = opt("steps", "menu,select,world,play");
fs.mkdirSync(outDir, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = [];
const errors = [];

function startServer() {
	const srv = spawn("python3", [path.join(here, "serve_web.py"), path.join(root, "build", "web"), "--port", String(port)], {
		stdio: ["ignore", "pipe", "pipe"],
		env: { ...process.env, SERVE_QUIET: "1" },
	});
	return new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error("server did not start")), 10000);
		srv.stdout.on("data", (d) => {
			if (String(d).includes("serving")) {
				clearTimeout(t);
				resolve(srv);
			}
		});
		srv.on("exit", (c) => reject(new Error("server exited " + c)));
	});
}

let srvProc = null;
let browserRef = null;

async function main() {
	const srv = await startServer();
	srvProc = srv;
	const base = devices[deviceName];
	if (!base) throw new Error("unknown device " + deviceName);
	// Landscape: swap the viewport.
	const vp = { width: Math.max(base.viewport.width, base.viewport.height), height: Math.min(base.viewport.width, base.viewport.height) };
	const browser = await chromium.launch({
		args: ["--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"],
	});
	browserRef = browser;
	const context = await browser.newContext({ ...base, viewport: vp, screen: vp, isMobile: true, hasTouch: true });
	const page = await context.newPage();
	page.on("console", (m) => {
		const line = `[${m.type()}] ${m.text()}`;
		log.push(line);
		if (m.type() === "error" || /SCRIPT ERROR|Parse Error/.test(m.text())) errors.push(line);
	});
	page.on("pageerror", (e) => errors.push("[pageerror] " + e.message));
	const cdp = await context.newCDPSession(page);
	const scale = vp.height / 1080.0; // design px -> CSS px (wide phones: height-bound)
	const designW = vp.width / scale;
	const at = (x, y) => ({ x: x * scale, y: y * scale });
	const shot = async (name) => {
		const p = path.join(outDir, name + ".png");
		const t = Date.now();
		await page.screenshot({ path: p, timeout: 300000 });
		const dt = (Date.now() - t) / 1000;
		console.log(`SCREENSHOT: ${p}${dt > 5 ? ` (page blocked ${dt.toFixed(0)} s)` : ""} at ${((Date.now() - t0) / 1000).toFixed(0)} s`);
	};
	const touch = async (type, points) => {
		await cdp.send("Input.dispatchTouchEvent", {
			type,
			touchPoints: points.map((p, i) => ({ x: p.x, y: p.y, id: p.id ?? i, radiusX: 6, radiusY: 6, force: 1 })),
		});
	};
	const tap = async (x, y, holdMs = 90) => {
		const p = at(x, y);
		await touch("touchStart", [p]);
		await sleep(holdMs);
		await touch("touchEnd", []);
	};
	const drag = async (id, from, to, n = 8, holdEnd = 0, keep = []) => {
		const a = at(from[0], from[1]);
		const b = at(to[0], to[1]);
		await touch("touchStart", [...keep, { ...a, id }]);
		for (let i = 1; i <= n; i++) {
			const t = i / n;
			await touch("touchMove", [...keep, { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, id }]);
			await sleep(40);
		}
		if (holdEnd > 0) await sleep(holdEnd);
	};

	const t0 = Date.now();
	console.log(`device ${deviceName} landscape ${vp.width}x${vp.height} css, dpr ${base.deviceScaleFactor}, design ${designW.toFixed(0)}x1080`);
	await page.goto(`http://127.0.0.1:${port}/index.html`, { waitUntil: "load" });
	// Boot: the loader's status overlay is removed once the engine started.
	await page.waitForFunction(() => !document.getElementById("status"), null, { timeout: bootTimeout });
	console.log(`engine started after ${((Date.now() - t0) / 1000).toFixed(1)} s`);
	const glInfo = await page.evaluate(() => {
		const c = document.createElement("canvas");
		const gl = c.getContext("webgl2");
		if (!gl) return "no webgl2";
		const d = gl.getExtension("WEBGL_debug_renderer_info");
		return d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
	});
	console.log("WebGL2 renderer:", glInfo);
	// Main menu: panorama + options (wait for the Router fade).
	await sleep(parseInt(opt("menu-wait", "25"), 10) * 1000);
	await shot("web_01_main_menu");
	if (steps.includes("settings")) {
		// 03 SETTINGS by tap, the CONTROLS tab, a drag to scroll its rows, then CANCEL.
		await tap(400, 801);
		await sleep(5000);
		await shot("web_01b_settings");
		const tabX = parseFloat(opt("controls-tab-x", "1677"));
		const tabY = parseFloat(opt("controls-tab-y", "135"));
		await tap(tabX, tabY);
		await sleep(3000);
		await shot("web_01c_settings_controls");
		await drag(5, [520, 740], [520, 330], 12, 300);
		await touch("touchEnd", []);
		await sleep(2500);
		await shot("web_01d_settings_scrolled");
		await tap(parseFloat(opt("cancel-x", "1700")), parseFloat(opt("cancel-y", "985")));
		await sleep(3000);
		await shot("web_01e_back_to_menu");
	}
	if (steps.includes("select")) {
		// 01 ENTER THE WORLD (first option; design ~ (440, 602)).
		await tap(440, 602);
		await sleep(parseInt(opt("select-wait", "30"), 10) * 1000);
		await shot("web_02_element_select");
		// Tap the third card (FIREBENDER) to choose it, then BEGIN.
		await tap(designW / 2 + 240, 560);
		await sleep(4000);
		await shot("web_03_element_chosen");
		await tap(designW / 2, 1080 - 51);
		if (steps.includes("world")) {
			await sleep(parseInt(opt("world-wait", "150"), 10) * 1000);
			await shot("web_04_world_arrival");
			// Skip the arrival cinematic (tap anywhere), then wait for control.
			await tap(designW * 0.5, 540);
			await sleep(20000);
			await shot("web_05_gameplay");
			if (steps.includes("play")) {
				// Stick: thumb down at the rest spot, push forward and hold while looking.
				const stick = [118 + 110, 1080 - 118 - 150];
				await drag(0, stick, [stick[0], stick[1] - 140], 6, 1500);
				await shot("web_06_stick_run");
				const keep = [{ ...at(stick[0], stick[1] - 140), id: 0 }];
				await drag(1, [designW * 0.62, 380], [designW * 0.62 - 260, 380], 10, 0, keep);
				await touch("touchEnd", keep);
				await sleep(300);
				await touch("touchEnd", []);
				// Strike x3 (design: 220,210 from the bottom-right corner).
				for (let i = 0; i < 3; i++) {
					await tap(designW - 220, 1080 - 210, 80);
					await sleep(350);
				}
				await shot("web_07_strike");
				// Heavy hold.
				const hv = at(designW - 415, 1080 - 240);
				await touch("touchStart", [hv]);
				await sleep(900);
				await touch("touchEnd", []);
				await sleep(600);
				await shot("web_08_heavy");
				// Pause button (top-right), then RESUME by tap.
				await tap(designW - 66, 64);
				await sleep(2500);
				await shot("web_09_pause");
				await tap(440, 312);
				await sleep(2000);
				await shot("web_10_resumed");
			}
		}
	}
	await browser.close();
	srv.kill();
	fs.writeFileSync(path.join(outDir, "console.log"), log.join("\n"));
	console.log(`console lines: ${log.length}, errors: ${errors.length}`);
	for (const e of errors.slice(0, 40)) console.log("  " + e);
	const scriptErrors = errors.filter((e) => /SCRIPT ERROR|Parse Error|pageerror/.test(e));
	console.log(scriptErrors.length ? "WEB SMOKE FAILED" : "WEB SMOKE PASSED");
	process.exit(scriptErrors.length ? 1 : 0);
}

main().catch(async (e) => {
	console.error(e);
	try {
		if (browserRef) await browserRef.close();
	} catch (_) {}
	if (srvProc) srvProc.kill();
	try {
		fs.writeFileSync(path.join(outDir, "console.log"), log.join("\n"));
	} catch (_) {}
	console.log("WEB SMOKE FAILED");
	process.exit(1);
});
