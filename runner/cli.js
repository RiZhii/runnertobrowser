const axios = require('axios');
const { chromium } = require('playwright');
const { loadPlan, executeStep } = require('./runner');

const args = parseArgs(process.argv.slice(2));
const PLAN_FILE = args.plan;

if (!PLAN_FILE) {
  console.error("Usage: node cli.js --plan <file>");
  process.exit(1);
}

// RETRY LOGIC (CRITICAL)
async function getDebuggerUrl(retries = 30) {
  for (let i = 0; i < retries; i++) {
    try {
      const res = await axios.get("http://browser-box:3000/json");

      if (res.data.length > 0) {
        console.log("CDP endpoint ready");
        return res.data[0].webSocketDebuggerUrl;
      }
    } catch (e) {}

    console.log(`Waiting for browser... (${i+1})`);
    await new Promise(r => setTimeout(r, 2000));
  }

  throw new Error("Browser not ready");
}

async function run() {
  console.log("\n🚀 ENTERPRISE RUNNER STARTED\n");

  const plan = loadPlan(PLAN_FILE);

  // ✅ GET WS URL
  let wsurl = await getDebuggerUrl();

  console.log("original WS URL:", wsurl);

  const urlObj = new URL(wsurl);
  
  urlObj.hostname = "browser-box";
  urlObj.port = "3000";

  wsurl = urlObj.toString();

  console.log("Final WS URL:", wsurl);

  const browser = await chromium.connectOverCDP(wsurl);

  console.log("browser connected");

  // ✅ ALWAYS CREATE CONTEXT
  const contexts = browser.contexts();

  if (contexts.length === 0) {
    throw new Error("No context found");
  }

  const pages = contexts[0].pages();

  if (pages.length === 0) {
    throw new Error("No page found in browser");
  }

  const page = pages[0];

  console.log("page created");

  await page.goto("https://www.odoo.com/");

  // ===== EXECUTION =====
  let passed = 0, failed = 0;

  for (let i = 0; i < plan.steps.length; i++) {
    const step = plan.steps[i];
    const start = Date.now();

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
      console.error("Step failed:", err.message);
    }
  }

  console.log(`\nTotal: ${plan.steps.length} | Passed: ${passed} | Failed: ${failed}`);

  await browser.close();
}

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

run().catch(err => {
  console.error("Fatal:", err.message);
  process.exit(1);
});