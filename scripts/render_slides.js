#!/usr/bin/env node
/**
 * VOX Slide Renderer — renders each slide to PNG via headless Chrome,
 * pixel-perfect match with what's displayed in the VOX editor.
 *
 * Usage: node render_slides.js <deck_json_file> <output_dir>
 * Output: slide-0.png, slide-1.png, ... in output_dir
 */
const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const SLIDE_W = 1280;
const SLIDE_H = 720;

// Read render engine JS from the Rails partial (strip ERB tags if any)
const RENDER_ENGINE_PATH = path.join(__dirname, '../app/views/admin/content_outlines/_slide_render_engine.html.erb');

function loadRenderEngine() {
  if (!fs.existsSync(RENDER_ENGINE_PATH)) return '';
  return fs.readFileSync(RENDER_ENGINE_PATH, 'utf8');
}

function buildSlideHtml(deck, slideIndex, renderEngineJs) {
  const slide = deck.slides[slideIndex];
  const bg = slide.background || { type: 'solid', color: '#ffffff' };
  const bgCss = bg.type === 'gradient' ? `background:${bg.value}` : `background:${bg.color || '#fff'}`;

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { width: ${SLIDE_W}px; height: ${SLIDE_H}px; overflow: hidden; }
  /* System fonts fallback — headless Chrome doesn't have Inter/Nunito */
  #stage {
    position: relative;
    width: ${SLIDE_W}px;
    height: ${SLIDE_H}px;
    overflow: hidden;
    ${bgCss};
  }
</style>
</head>
<body>
<div id="stage"></div>
<script>
  var deck = ${JSON.stringify(deck)};
  var slides = deck.slides || [];
  var editorMode = false;
  var SW = 10.0, SH = 5.625;
  var PX = function(inch) { return Math.round(inch * 128); };
  var PT = function(pt)   { return Math.round(pt * 128 / 72); };

  function _hexLuminance(hex) {
    var c = hex.replace('#','');
    if (c.length===3) c=c[0]+c[0]+c[1]+c[1]+c[2]+c[2];
    var r=parseInt(c.substr(0,2),16)/255,g=parseInt(c.substr(2,2),16)/255,b=parseInt(c.substr(4,2),16)/255;
    var f=function(x){return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4);};
    return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b);
  }
  function _darken(hex,amt){
    hex=hex.replace('#','');
    if(hex.length===3)hex=hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
    var r=Math.max(0,parseInt(hex.substr(0,2),16)-amt);
    var g=Math.max(0,parseInt(hex.substr(2,2),16)-amt);
    var b=Math.max(0,parseInt(hex.substr(4,2),16)-amt);
    return '#'+[r,g,b].map(function(v){return v.toString(16).padStart(2,'0');}).join('');
  }
  function applyThemeAccent() {
    var accent=(deck.theme&&deck.theme.accent)||'#6366f1';
    if(_hexLuminance(accent)>0.55)accent='#6366f1';
    document.documentElement.style.setProperty('--vox-accent',accent);
    document.documentElement.style.setProperty('--vox-accent-dk',_darken(accent,20));
  }
  function _accent(){return getComputedStyle(document.documentElement).getPropertyValue('--vox-accent').trim()||'#6366f1';}
  function _accentDk(){return getComputedStyle(document.documentElement).getPropertyValue('--vox-accent-dk').trim()||'#4f46e5';}

  ${renderEngineJs}

  function renderSlide(idx) {
    var s = slides[idx];
    if (!s) return '';
    var bg = s.background || {type:'solid',color:'#ffffff'};
    var bgCss = bg.type==='gradient' ? 'background:'+bg.value+';' : 'background:'+(bg.color||'#fff')+';';
    var els = (s.elements||[]).sort(function(a,b){return (a.z||2)-(b.z||2);});
    var content = els.map(function(e){return renderEl(e,idx);}).join('');
    return '<div style="position:absolute;inset:0;'+bgCss+'">'+content+'</div>';
  }

  applyThemeAccent();
  var stage = document.getElementById('stage');
  stage.innerHTML = renderSlide(${slideIndex});

  // Apply pending images (base64)
  applyPendingImages();
  window._renderDone = true;
</script>
</body>
</html>`;
}

async function renderSlides(deckJsonPath, outputDir) {
  const deckJson = fs.readFileSync(deckJsonPath, 'utf8');
  const deck = JSON.parse(deckJson);
  const slides = deck.slides || [];

  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });

  const renderEngineJs = loadRenderEngine();

  // Find Chrome: prefer system Chrome (works on macOS), fall back to puppeteer bundled
  function findChrome() {
    const candidates = [
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/Applications/Chromium.app/Contents/MacOS/Chromium',
      '/usr/bin/google-chrome', '/usr/bin/chromium-browser', '/usr/bin/chromium',
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return c;
    }
    return puppeteer.executablePath();
  }

  const browser = await puppeteer.launch({
    headless: true,
    executablePath: findChrome(),
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-web-security',
           '--disable-features=IsolateOrigins,site-per-process',
           '--font-render-hinting=none', '--disable-gpu']
  });

  try {
    for (let i = 0; i < slides.length; i++) {
      const page = await browser.newPage();
      await page.setViewport({ width: SLIDE_W, height: SLIDE_H, deviceScaleFactor: 2 });

      const html = buildSlideHtml(deck, i, renderEngineJs);
      await page.setContent(html, { waitUntil: 'domcontentloaded', timeout: 15000 });

      // Wait for render complete signal
      await page.waitForFunction('window._renderDone === true', { timeout: 5000 }).catch(() => {});

      // Give fonts a moment to render (base64 images are instant)
      await new Promise(r => setTimeout(r, 500));

      const outPath = path.join(outputDir, `slide-${i}.png`);
      await page.screenshot({ path: outPath, type: 'png', clip: { x: 0, y: 0, width: SLIDE_W, height: SLIDE_H } });
      await page.close();

      process.stderr.write(`[render] slide ${i+1}/${slides.length} → ${outPath}\n`);
    }
  } finally {
    await browser.close();
  }

  console.log(outputDir);  // stdout: output dir path for Ruby to read
}

const deckJsonPath = process.argv[2];
const outputDir    = process.argv[3];

if (!deckJsonPath || !outputDir) {
  process.stderr.write('Usage: node render_slides.js <deck_json_file> <output_dir>\n');
  process.exit(1);
}

renderSlides(deckJsonPath, outputDir).catch(err => {
  process.stderr.write(`[render] ERROR: ${err.message}\n`);
  process.exit(1);
});
