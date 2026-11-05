# Builds ios/ChipmunkChallenge/Web/index.html from web/chipmunk-challenge.html.
# Usage: python3 tools/make_ios_page.py web/chipmunk-challenge.html ios/ChipmunkChallenge/Web/index.html
import sys
src,dst=sys.argv[1],sys.argv[2]
h=open(src,encoding='utf-8').read()
def rep(old,new):
    global h
    assert h.count(old)==1,(old[:60],h.count(old)); h=h.replace(old,new)
rep('<meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover">',
    '<meta name=viewport content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">')
rep('<link rel="preconnect" href="https://fonts.googleapis.com">\n','')
rep('<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lilita+One&family=Nunito:wght@500;700;800&family=JetBrains+Mono:wght@400;600&display=swap">',
    '<link rel="stylesheet" href="fonts/fonts.css">\n<style>/* iOS build: hide the solver workbench, single column, no text selection or tap flash */\n.bench{display:none!important}.app{grid-template-columns:minmax(0,1fr)!important}.game{max-width:520px;margin:0 auto;width:100%}\nhtml,body{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent;overscroll-behavior:none}\n</style>')
rep("  try{if(navigator.vibrate)navigator.vibrate(10)}catch(e){}\n",
    "  try{const n=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.haptic;if(n){n.postMessage('tick');return}}catch(e){}\n  try{if(navigator.vibrate)navigator.vibrate(10)}catch(e){}\n")
open(dst,'w',encoding='utf-8').write(h)
