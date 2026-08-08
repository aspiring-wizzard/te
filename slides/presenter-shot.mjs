// Screenshot presenter mode with a chosen layout, to check the notes pane.
//   node presenter-shot.mjs http://localhost:3077 2 2
// args: baseUrl, slidevPresenterLayout (1-3), slideNo
import { chromium } from 'playwright-chromium'

const base = process.argv[2] ?? 'http://localhost:3077'
const layout = process.argv[3] ?? '2'
const slide = process.argv[4] ?? '2'

const browser = await chromium.launch()
const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 } })
// presenterLayout is a useLocalStorage ref — seed it before the app boots.
await ctx.addInitScript(l => localStorage.setItem('slidev-presenter-layout', l), layout)
const page = await ctx.newPage()

await page.goto(`${base}/presenter/${slide}`, { waitUntil: 'networkidle' })
await page.waitForTimeout(2500)

const info = await page.evaluate(() => {
  const g = document.querySelector('.grid-container')
  const note = document.querySelector('.slidev-note')
  const r = el => el ? el.getBoundingClientRect() : null
  const gn = r(note)
  return {
    layoutClass: g ? g.className : null,
    cols: g ? getComputedStyle(g).gridTemplateColumns : null,
    noteBox: gn ? `${Math.round(gn.width)}x${Math.round(gn.height)}` : null,
    noteListItems: document.querySelectorAll('.slidev-note li').length,
    noteParagraphs: document.querySelectorAll('.slidev-note p').length,
  }
})
console.log(JSON.stringify(info, null, 2))
await page.screenshot({ path: `presenter-${layout}-${slide}.png` })
await browser.close()
