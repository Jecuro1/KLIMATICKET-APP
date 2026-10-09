const { chromium } = require('playwright');
(async () => {
  const exe = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
  const browser = await chromium.launch({ executablePath: require('fs').existsSync(exe) ? exe : undefined });
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  for (const [svg, out] of [['icon.svg', 'AppIcon.png'], ['icon-dark.svg', 'AppIcon-Dark.png'], ['icon-tinted.svg', 'AppIcon-Tinted.png']]) {
    await page.goto('file://' + process.cwd() + '/' + svg);
    await page.screenshot({ path: out, omitBackground: false });
  }
  // preview with iOS mask
  await page.goto('about:blank');
  await page.setContent(`<html><body style="margin:0;background:#888;display:flex;gap:40px;padding:40px">
    ${['AppIcon.png','AppIcon-Dark.png','AppIcon-Tinted.png'].map(f=>`<img src="file://${process.cwd()}/${f}" style="width:280px;height:280px;border-radius:62px">`).join('')}</body></html>`);
  await page.setViewportSize({ width: 1000, height: 360 });
  await page.screenshot({ path: 'preview.png' });
  await browser.close();
})();
