const axios = require('axios');
const { chromium } = require('playwright');
const { loadPlan, executeStep } = require('./runner');

const args = parseArgs(process.argv.slice(2));
const PLAN_FILE = args.plan;

if (!PLAN_FILE) {
  console.error("Usage: node cli.js --plan <file>");
  process.exit(1);
}

// -----------------------------
// Wait for CDP endpoint
// -----------------------------
async function getDebuggerUrl(retries = 30) {
  for (let i = 0; i < retries; i++) {
    try {
      const res = await axios.get("http://browser-box:3000/json");

      if (Array.isArray(res.data) && res.data.length > 0) {
        const ws = res.data[0].webSocketDebuggerUrl;

        if (ws) {
          console.log(`CDP ready (${res.data.length} targets)`);
          return ws;
        }
      }
    } catch (e) {}

    console.log(`Waiting for browser... (${i + 1}/${retries})`);
    await new Promise(r => setTimeout(r, 2000));
  }

  throw new Error("Browser CDP not ready");
}

// -----------------------------
// MAIN RUN
// -----------------------------
async function run() {
  console.log("\n🚀 RUNNER STARTED\n");

  const plan = loadPlan(PLAN_FILE);

  // -----------------------------
  // Get WS URL
  // -----------------------------
  let wsurl = await getDebuggerUrl();

  console.log("Original WS:", wsurl);

  const urlObj = new URL(wsurl);
  urlObj.hostname = "browser-box";
  urlObj.port = "3000";

  wsurl = urlObj.toString();

  console.log("Proxy WS:", wsurl);

  // -----------------------------
  // Connect to browser
  // -----------------------------
  const browser = await chromium.connectOverCDP(wsurl);
  console.log("Browser connected");

  // -----------------------------
  // ALWAYS CREATE FRESH CONTEXT + PAGE
  // -----------------------------
  const context = await browser.newContext();
  const page = await context.newPage();

  console.log("Fresh page created");

  // -----------------------------
  // Navigate (runner owns this)
  // -----------------------------
  await page.goto(plan.meta?.start_url || "https://www.odoo.com/", {
    waitUntil: "domcontentloaded",
    timeout: 30000
  });

  console.log("Navigation complete");

  // -----------------------------
  // Execute Steps
  // -----------------------------
  let passed = 0;
  let failed = 0;

  for (let i = 0; i < plan.steps.length; i++) {
    const step = plan.steps[i];

    try {
      await executeStep(page, step, {
        verbose: true,
        _allSteps: plan.steps,
        _stepIndex: i,
        _prevStep: plan.steps[i - 1]
      });

      passed++;
    } catch (err) {
      failed++;
      console.error(`Step ${i + 1} failed:`, err.message);
    }
  }

  console.log(`\nTotal: ${plan.steps.length} | Passed: ${passed} | Failed: ${failed}`);

  await browser.close();
}

// -----------------------------
// ARG PARSER
// -----------------------------
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      out[key] = argv[i + 1] && !argv[i + 1].startsWith('--')
        ? argv[++i]
        : true;
    }
  }
  return out;
}

// -----------------------------
// START
// -----------------------------
run().catch(err => {
  console.error("Fatal:", err.message);
  process.exit(1);
});