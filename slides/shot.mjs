// Screenshot given slides from a running dev server — ground truth for what the
// presenter actually sees, independent of the `slidev export` pipeline.
//
//   node shot.mjs http://localhost:3033 7 4
import { chromium } from 'playwright-chromium'

const base = process.argv[2] ?? 'http://localhost:3033'
const slides = process.argv.slice(3).map(Number)

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } })

for (const n of slides) {
  await page.goto(`${base}/${n}`, { waitUntil: 'networkidle' })
  await page.waitForTimeout(2500)
  const info = await page.evaluate(() => {
    const m = document.querySelector('.mermaid')
    const svg = document.querySelector('.mermaid svg')
    return {
      hasMermaidEl: !!m,
      hasSvg: !!svg,
      mermaidText: m ? m.textContent.slice(0, 120) : null,
      svgW: svg?.getBoundingClientRect().width ?? 0,
      svgH: svg?.getBoundingClientRect().height ?? 0,
    }
  })
  console.log(`slide ${n}:`, JSON.stringify(info))
  await page.screenshot({ path: `shot-${n}.png` })
}
await browser.close()
