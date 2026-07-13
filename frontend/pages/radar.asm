bits 64
default rel

%ifdef MACOS
  %define radar_html _radar_html
%endif

section .data
    radar_page db '<!DOCTYPE html>', 13, 10
               db '<html>', 13, 10
               db '<head>', 13, 10
               db '<meta charset="utf-8">', 13, 10
               db '<meta name="viewport" content="width=device-width, initial-scale=1.0">', 13, 10
               db '<title>24Scope Radar</title>', 13, 10
               db '<link rel="stylesheet" href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css">', 13, 10
               db '<style>', 13, 10
               db ':root{color-scheme:dark;--bg:#0a0e17;--panel:rgba(10,16,28,.92);--text:#e8f0ff;--muted:#8aa0b8;--cyan:#06b6d4;'
               db '--border:rgba(122,161,196,.22)}', 13, 10
               db '*{box-sizing:border-box}html,body{margin:0;height:100%;background:var(--bg);color:var(--text);font-family:Segoe UI,IBM '
               db 'Plex Sans,sans-serif}', 13, 10
               db '#app{display:flex;flex-direction:column;height:100%}', 13, 10
               db '.topbar{display:flex;justify-content:space-between;align-items:center;gap:16px;padding:12px 18px;border-bottom:1px '
               db 'solid var(--border);background:linear-gradient(180deg,rgba(12,20,34,.98),rgba(8,12,22,.96))}', 13, 10
               db '.eyebrow{margin:0;color:var(--cyan);text-transform:uppercase;letter-spacing:.2em;font-size:.7rem;font-weight:700}', 13, 10
               db '.topbar h1{margin:2px 0 0;font-size:1.35rem;letter-spacing:-.03em}', 13, 10
               db '.topbar-right{display:flex;align-items:center;gap:12px}', 13, 10
               db '.pill{padding:6px 12px;border-radius:999px;border:1px solid rgba(6,182,212,.35);background:rgba(6,182,212,.12);'
               db 'color:#b8f4ff;font-size:.85rem;font-weight:600}', 13, 10
               db '.home-link{color:var(--muted);text-decoration:none;font-size:.9rem}', 13, 10
               db '#map-wrap{position:relative;flex:1;min-height:0}#map{width:100%;height:100%}', 13, 10
               db '.toolbar{position:absolute;top:12px;left:12px;z-index:10;display:flex;flex-direction:column;gap:6px}', 13, 10
               db '.tool{padding:6px 12px;border:1px solid var(--border);border-radius:6px;background:#1a2332;color:#a8bad0;font-size:12px;'
               db 'font-weight:600;cursor:pointer}', 13, 10
               db '.tool.active{background:var(--cyan);color:#0a0e17;border-color:var(--cyan)}', 13, 10
               db '.tool.measure-on{background:#f472b6;color:#0a0e17;border-color:#f472b6}', 13, 10
               db '.measure-bar{position:absolute;bottom:16px;left:50%;transform:translateX(-50%);z-index:10;display:flex;'
               db 'align-items:center;gap:16px;padding:8px 16px;border:1px solid #f472b6;border-radius:10px;background:rgba(12,18,30,.94);'
               db 'font-size:13px;font-weight:600;box-shadow:0 4px 24px rgba(0,0,0,.5)}', 13, 10
               db '.hidden{display:none!important}', 13, 10
               db '#measure-dist{color:#f472b6}#measure-brg{color:var(--muted)}', 13, 10
               db '#btn-measure-clear{background:none;border:none;color:var(--muted);cursor:pointer;font-size:12px}', 13, 10
               db '.selected-panel{position:absolute;top:12px;right:12px;z-index:10;min-width:180px;padding:12px 14px;border:1px solid '
               db 'var(--border);border-radius:10px;background:var(--panel);box-shadow:0 8px 32px rgba(0,0,0,.45)}', 13, 10
               db '.sel-callsign{font-size:1.05rem;font-weight:700;color:#22c55e}', 13, 10
               db '.sel-meta{margin-top:6px;color:var(--muted);font-size:.85rem;line-height:1.45}', 13, 10
               db '</style>', 13, 10
               db '</head>', 13, 10
               db '<body>', 13, 10
               db '<div id="app">', 13, 10
               db '<header class="topbar">', 13, 10
               db '<div><p class="eyebrow">24Scope</p><h1>Radar Map</h1></div>', 13, 10
               db '<div class="topbar-right"><span id="ac-count" class="pill">0 tracks</span><a class="home-link" href="/">Home</a></div>', 13, 10
               db '</header>', 13, 10
               db '<div id="map-wrap">', 13, 10
               db '<div id="map"></div>', 13, 10
               db '<div class="toolbar">', 13, 10
               db '<button type="button" id="btn-labels" class="tool active">Fixes ON</button>', 13, 10
               db '<button type="button" id="btn-measure" class="tool">Measure</button>', 13, 10
               db '</div>', 13, 10
               db '<div id="measure-bar" class="measure-bar hidden"><span id="measure-dist"></span><span id="measure-brg"></span><button '
               db 'type="button" id="btn-measure-clear">Clear</button></div>', 13, 10
               db '<div id="selected" class="selected-panel hidden"><div class="sel-callsign" id="sel-cs"></div><div class="sel-meta" '
               db 'id="sel-meta"></div></div>', 13, 10
               db '</div>', 13, 10
               db '</div>', 13, 10
               db '<script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>', 13, 10
               db '<script>', 13, 10
               db 13, 10
               db 'const STUDS_TO_METERS = 1852 / 3307.14286;', 13, 10
               db 'const STUDS_PER_SEC = 0.5442765;', 13, 10
               db 'const DEG_TO_RAD = Math.PI / 180;', 13, 10
               db 'const AIRPORTS = [{"icao":"IRFD","name":"Greater Rockford","region":"Rockford","x":-2925,"y":20082,"hasILS":true},{'
               db '"icao":"IGAR","name":"Air Base Garry","region":"Rockford","x":-16272,"y":23655,"hasILS":false},{"icao":"IBLT",'
               db '"name":"Boltic Airfield","region":"Rockford","x":-11226,"y":17466,"hasILS":false},{"icao":"IMLR","name":"Mellor",'
               db '"region":"Rockford","x":-19365,"y":14766,"hasILS":true},{"icao":"ITRC","name":"Training Centre","region":"Rockford",'
               db '"x":-1995,"y":30057,"hasILS":true},{"icao":"ILAR","name":"Larnaca","region":"Cyprus","x":21330,"y":32406,"hasILS":true},'
               db '{"icao":"IPAP","name":"Paphos","region":"Cyprus","x":31731,"y":34272,"hasILS":true},{"icao":"IIAB","name":"McConnell '
               db 'AFB","region":"Cyprus","x":23220,"y":40350,"hasILS":false},{"icao":"IGRV","name":"Grindavik","region":"Grindavik",'
               db '"x":-43158,"y":-2757,"hasILS":true},{"icao":"IPPH","name":"Perth","region":"Perth","x":18105,"y":-20409,"hasILS":true},{'
               db '"icao":"ILKL","name":"Lukla","region":"Perth","x":22623,"y":-16512,"hasILS":false},{"icao":"ITKO","name":"Tokyo",'
               db '"region":"Orenji","x":-7368,"y":-31953,"hasILS":true},{"icao":"IDCS","name":"Saba","region":"Orenji","x":-4854,'
               db '"y":-44892,"hasILS":false},{"icao":"IZOL","name":"Izolirani","region":"Izolirani","x":44772,"y":3420,"hasILS":true},{'
               db '"icao":"IJAF","name":"Al Najaf","region":"Izolirani","x":46182,"y":222,"hasILS":true},{"icao":"ISCM","name":"RAF '
               db 'Scampton","region":"Izolirani","x":36111,"y":-5001,"hasILS":false},{"icao":"IBTH","name":"Saint Barthelemy",'
               db '"region":"SaintBarthelemy","x":5778,"y":-4509,"hasILS":false},{"icao":"ISAU","name":"Sauthemptona",'
               db '"region":"Sauthemptona","x":-46056,"y":27501,"hasILS":false}];', 13, 10
               db 'const WAYPOINTS = [{"name":"SHELL","x":-26493,"y":-40395},{"name":"NIKON","x":-12240,"y":-42360},{"name":"CHILY",'
               db '"x":3315,"y":-40650},{"name":"SHIBA","x":-18480,"y":-37746},{"name":"LETSE","x":-4908,"y":-35184},{"name":"HONDA",'
               db '"x":6171,"y":-35220},{"name":"ASTRO","x":-15771,"y":-30717},{"name":"GULEG","x":-22233,"y":-25842},{"name":"PIPER",'
               db '"x":-13644,"y":-25113},{"name":"ONDER","x":-5997,"y":-23073},{"name":"KNIFE","x":1062,"y":-24798},{"name":"TUDEP",'
               db '"x":-16383,"y":-18261},{"name":"ALLRY","x":6009,"y":-18204},{"name":"CRAZY","x":18213,"y":-35193},{"name":"WOTAN",'
               db '"x":33834,"y":-33351},{"name":"WAGON","x":43389,"y":-30123},{"name":"WELLS","x":24522,"y":-26283},{"name":"SQUID",'
               db '"x":36015,"y":-26115},{"name":"ZESTA","x":46035,"y":-23397},{"name":"TINDR","x":10191,"y":-22410},{"name":"NOONU",'
               db '"x":28935,"y":-19086},{"name":"KELLA","x":33924,"y":-18804},{"name":"STRAX","x":11907,"y":-17349},{"name":"TALIS",'
               db '"x":25524,"y":-11688},{"name":"SISTA","x":31983,"y":-12702},{"name":"UDMUG","x":50277,"y":-14061},{"name":"ROSMO",'
               db '"x":39513,"y":-9591},{"name":"LLIME","x":53373,"y":-8349},{"name":"CAMEL","x":21027,"y":-6321},{"name":"DUNKS",'
               db '"x":28113,"y":-5961},{"name":"MORRD","x":50298,"y":-1980},{"name":"CYRIL","x":26388,"y":438},{"name":"DOGGO","x":35742,'
               db '"y":7254},{"name":"ABSRS","x":54840,"y":6690},{"name":"BILLO","x":46824,"y":11157},{"name":"JUSTY","x":38118,"y":16035},'
               db '{"name":"CHAIN","x":54840,"y":18969},{"name":"RENTS","x":25209,"y":22182},{"name":"GRASS","x":17583,"y":25671},{'
               db '"name":"JACKI","x":33678,"y":29502},{"name":"DEBUG","x":46734,"y":29505},{"name":"BOBUX","x":39423,"y":35382},{'
               db '"name":"NUBER","x":54747,"y":36882},{"name":"AQWRT","x":14826,"y":36321},{"name":"FORIA","x":6009,"y":42165},{'
               db '"name":"MUONE","x":38181,"y":42195},{"name":"JAZZR","x":46638,"y":42240},{"name":"FORCE","x":20460,"y":48891},{'
               db '"name":"MASEV","x":29235,"y":48891},{"name":"ALTRS","x":35931,"y":48891},{"name":"CAWZE","x":18669,"y":7617},{'
               db '"name":"ANYMS","x":14163,"y":18333},{"name":"GERLD","x":-16539,"y":-15387},{"name":"RENDR","x":-12456,"y":-14379},{'
               db '"name":"JOOPY","x":-2937,"y":-15414},{"name":"PROBE","x":-8403,"y":-10497},{"name":"DINER","x":3075,"y":-9945},{'
               db '"name":"WELSH","x":-12498,"y":-4509},{"name":"INDEX","x":-7029,"y":-699},{"name":"GAVIN","x":5388,"y":1389},{'
               db '"name":"SILVA","x":16503,"y":1575},{"name":"OCEEN","x":10668,"y":5256},{"name":"ENDER","x":-20991,"y":684},{'
               db '"name":"SUNST","x":-26238,"y":5082},{"name":"KENED","x":-12495,"y":3669},{"name":"SETHR","x":2337,"y":7653},{'
               db '"name":"BUCFA","x":-20472,"y":8718},{"name":"KUNAV","x":-12447,"y":9489},{"name":"SAWPE","x":-28527,"y":10803},{'
               db '"name":"ICTAM","x":-14313,"y":12456},{"name":"HAWFA","x":-8880,"y":11496},{"name":"QUEEN","x":-3297,"y":15606},{'
               db '"name":"BEANS","x":-28017,"y":18990},{"name":"LOGAN","x":-21063,"y":20553},{"name":"LAVNO","x":1188,"y":17634},{'
               db '"name":"ATPEV","x":4266,"y":16389},{"name":"JAMSI","x":7689,"y":22431},{"name":"MOGTA","x":-12255,"y":23361},{'
               db '"name":"EXMOR","x":-19848,"y":26751},{"name":"PEPUL","x":-9489,"y":28836},{"name":"GODLU","x":2301,"y":27399},{'
               db '"name":"LAZER","x":6984,"y":29328},{"name":"EMJAY","x":-15786,"y":36090},{"name":"ODOKU","x":-4803,"y":36078},{'
               db '"name":"TRELN","x":-11238,"y":45612},{"name":"REAPR","x":-2412,"y":44034},{"name":"HACKE","x":-54678,"y":20346},{'
               db '"name":"GEORG","x":-46344,"y":22878},{"name":"SEEKS","x":-37602,"y":25821},{"name":"HECKS","x":-56751,"y":30276},{'
               db '"name":"PACKT","x":-49680,"y":32220},{"name":"ALDER","x":-28989,"y":33447},{"name":"STACK","x":-40317,"y":35763},{'
               db '"name":"WASTE","x":-50265,"y":40611},{"name":"HOGGS","x":-30375,"y":39738},{"name":"BULLY","x":-34029,"y":-29853},{'
               db '"name":"FROOT","x":-40329,"y":-22335},{"name":"EURAD","x":-27699,"y":-20175},{"name":"BOBOS","x":-46806,"y":-16122},{'
               db '"name":"BLANK","x":-25092,"y":-14322},{"name":"THENR","x":-40452,"y":-12771},{"name":"ACRES","x":-51372,"y":-10767},{'
               db '"name":"YOUTH","x":-33150,"y":-8859},{"name":"UWAIS","x":-56427,"y":-5775},{"name":"EZYDB","x":-24729,"y":-4431},{'
               db '"name":"FRANK","x":-55854,"y":1920},{"name":"CELAR","x":-38040,"y":5070},{"name":"THACC","x":-55953,"y":10374},{'
               db '"name":"SHREK","x":-47022,"y":11247},{"name":"SPACE","x":-37644,"y":13071}];', 13, 10
               db 'const VORTACS = [{"name":"HANEDA","id":"HME","freq":"112.200","x":-8574,"y":-32031},{"name":"CROIS NOOB","id":"COC",'
               db '"freq":"","x":15048,"y":-27387},{"name":"PERTH","id":"PER","freq":"115.430","x":15786,"y":-20832},{"name":"BRAINSTORM",'
               db '"id":"BTM","freq":"","x":23988,"y":-19914},{"name":"ORANGE","id":"ORG","freq":"","x":18495,"y":-15279},{"name":"ROMIES",'
               db '"id":"ROM","freq":"","x":8283,"y":-10806},{"name":"RESURGE","id":"RES","freq":"","x":-864,"y":-4086},{"name":"VONARX",'
               db '"id":"VOX","freq":"","x":10806,"y":-4446},{"name":"HOTDOG","id":"HOT","freq":"","x":35349,"y":-4632},{"name":"TRESIN",'
               db '"id":"TRE","freq":"","x":34905,"y":690},{"name":"AL NAJAF","id":"NJF","freq":"112.450","x":45393,"y":183},{'
               db '"name":"IZOLIRANI","id":"IZO","freq":"117.530","x":44352,"y":3420},{"name":"DIZZIER","id":"DIZ","freq":"","x":48342,'
               db '"y":4560},{"name":"DETOX","id":"DET","freq":"","x":46527,"y":17787},{"name":"KINDLE","id":"KIN","freq":"","x":29349,'
               db '"y":27636},{"name":"LARNACA","id":"LCK","freq":"122.670","x":20712,"y":31773},{"name":"PAPHOS","id":"PFO",'
               db '"freq":"117.900","x":29994,"y":34413},{"name":"CANDLE","id":"CAN","freq":"","x":9366,"y":39216},{"name":"DIRECTOR",'
               db '"id":"DIR","freq":"","x":11997,"y":44199},{"name":"HUNTER","id":"HUT","freq":"","x":29511,"y":39537},{"name":"MELLOR",'
               db '"id":"MLR","freq":"125.700","x":-20286,"y":14640},{"name":"BLANK","id":"BLA","freq":"","x":-8784,"y":14955},{'
               db '"name":"ROCKFORD","id":"RFD","freq":"115.900","x":-4728,"y":20217},{"name":"GREY","id":"GRY","freq":"","x":-17034,'
               db '"y":23226},{"name":"TRAINING CENTRE","id":"TRN","freq":"127.730","x":-3423,"y":29943},{"name":"KROTEN","id":"KRT",'
               db '"freq":"","x":-51972,"y":24579},{"name":"SAUTHEMPTONA","id":"SAU","freq":"113.350","x":-46926,"y":27147},{'
               db '"name":"BARNIE","id":"BAR","freq":"","x":-38961,"y":30273},{"name":"DELIVERY","id":"DEL","freq":"","x":27828,"y":11349},'
               db '{"name":"CLEARANCE","id":"CLR","freq":"","x":20046,"y":14943},{"name":"GRINDAVIK","id":"GVK","freq":"112.320",'
               db '"x":-44550,"y":-3396},{"name":"GOLDEN","id":"GOL","freq":"","x":-48945,"y":-2394},{"name":"HAWKIN","id":"HAW","freq":"",'
               db '"x":-40545,"y":-6075}];', 13, 10
               db 'const BOUNDARIES = [{"points":[[-26168.786517284512,51531.027315541185],[-26039.63549648512,30737.71296683982],'
               db '[-34434.4518484453,23117.802739675968],[-34692.75389004407,1937.0353285764468],[-25652.182434086957,-4778.817752991694],'
               db '[8960.291140148844,4649.20676536358],[11543.31155613659,9040.34147254275],[13609.727888926787,12914.87209652437],'
               db '[15934.446263315758,22213.745594080257],[17096.80545051025,27767.23948845391],[3794.2503081733503,34095.63950762389],'
               db '[3923.4013289727372,51143.574253143015],[-26039.63549648512,51143.574253143015],[-26039.63549648512,'
               db '51143.574253143015]]},{"points":[[-34692.75389004407,18984.970074095574],[-51224.08455236565,13173.174138123144],'
               db '[-65688.99888189703,11752.512909329884],[-65301.54581949887,51272.7252739424],[-26039.63549648512,51531.027315541185],'
               db '[-26039.63549648512,51401.87629474179]]},{"points":[[-25523.031413287572,-5166.270815389869],[-20227.839560512693,'
               db '-16919.013708134116],[-31722.280411658165,-52693.84646956441],[-65559.84786109765,-52822.99749036379],'
               db '[-65559.84786109765,11494.210867731097],[-65559.84786109765,11494.210867731097]]},{"points":[[-20227.839560512693,'
               db '-17306.46677053228],[-18548.876290120657,-20406.091269717574],[11155.85849373843,-20406.091269717574],'
               db '[11155.85849373843,-52822.99749036379],[-31980.582453256942,-52952.14851116318],[-31980.582453256942,'
               db '-52952.14851116318]]},{"points":[[11285.009514537818,-20535.242290516966],[16321.899325713923,-18856.279020124934],'
               db '[20325.580970494928,-8395.04633537456],[26008.225885667973,-10590.613688964144],[35436.250404023245,'
               db '-10978.066751362305],[54033.99739913503,-21439.29943611268],[69402.96887426212,-20922.69535291513],[69144.66683266334,'
               db '-52693.84646956441],[11026.70747293904,-52822.99749036381],[11026.70747293904,-52822.99749036381]]},{'
               db '"points":[[20454.731991294302,-7620.140210578233],[26395.678948066117,-2970.703461800287],[23941.80955287776,'
               db '5294.961869360501],[11672.462576935963,9427.794534940895],[11543.311556136574,9427.794534940895]]},{'
               db '"points":[[24200.111594476533,4907.508806962338],[32078.32386323916,2582.790432573367],[39569.08306960363,'
               db '3099.3945157709168],[39569.08306960363,6457.321056554987],[37244.36469521465,8911.190451743347],[37631.817757612815,'
               db '15239.590470913325],[39181.630007205466,16401.94965810781],[16192.74830491452,22472.047635679017],[16192.74830491452,'
               db '22472.047635679017]]},{"points":[[39827.3851112024,16531.100678907198],[43960.217776782796,20534.782323688203],'
               db '[68886.36479106455,25184.21907246615],[69144.66683266332,51531.02731554117],[4052.552349772108,51401.87629474177],'
               db '[4052.552349772108,51401.87629474177]]}];', 13, 10
               db 'const PLANE_ICON_FILES = ["737","747","A300","A320","A330","A340","A3402","A350","A380","AN-225","B757","B777","B787",'
               db '"C17","Drone","GA","GC","Hele1","Hele2","hotairballon","ISS","Layer 17","PJ","old737","Prop","Prop2","RegionalJet",'
               db '"Satelite","SolarPlane","SuperSonic","flider"];', 13, 10
               db 'const DEFAULT_PLANE_ICON = "plane-GA";', 13, 10
               db 'const AIRCRAFT_TYPE_TO_ICON = {', 13, 10
               db '  "Boeing 737":"plane-737","Boeing 737 MAX":"plane-737","Boeing 747":"plane-747","Boeing 757":"plane-B757",', 13, 10
               db '  "Boeing 777":"plane-B777","Boeing 787":"plane-B787","Airbus A300":"plane-A300","Airbus A320":"plane-A320",', 13, 10
               db '  "Airbus A330":"plane-A330","Airbus A340":"plane-A340","Airbus A350":"plane-A350","Airbus A380":"plane-A380",', 13, 10
               db '  "Private Jet":"plane-PJ","Helicopter":"plane-Hele1","General Aviation":"plane-GA","Cessna":"plane-GA",', 13, 10
               db '  "Regional Jet":"plane-RegionalJet","Prop Plane":"plane-Prop","ISS":"plane-ISS"', 13, 10
               db '};', 13, 10
               db 13, 10
               db 'function projectStudsToLngLat(x, y) {', 13, 10
               db '  const lat = -(y * STUDS_TO_METERS) / 111111;', 13, 10
               db '  const lng = (x * STUDS_TO_METERS) / (111111 * Math.cos(lat * (Math.PI / 180)));', 13, 10
               db '  return [lng, lat];', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function getPlaneIconName(aircraftType) {', 13, 10
               db '  if (AIRCRAFT_TYPE_TO_ICON[aircraftType]) return AIRCRAFT_TYPE_TO_ICON[aircraftType];', 13, 10
               db '  const lower = (aircraftType || "").toLowerCase();', 13, 10
               db '  if (lower.includes("737")) return "plane-737";', 13, 10
               db '  if (lower.includes("747")) return "plane-747";', 13, 10
               db '  if (lower.includes("777")) return "plane-B777";', 13, 10
               db '  if (lower.includes("787")) return "plane-B787";', 13, 10
               db '  if (lower.includes("a320") || lower.includes("a319") || lower.includes("a321")) return "plane-A320";', 13, 10
               db '  if (lower.includes("a330")) return "plane-A330";', 13, 10
               db '  if (lower.includes("a350")) return "plane-A350";', 13, 10
               db '  if (lower.includes("a380")) return "plane-A380";', 13, 10
               db '  if (lower.includes("heli")) return "plane-Hele1";', 13, 10
               db '  if (lower.includes("private") || lower.includes("business")) return "plane-PJ";', 13, 10
               db '  return DEFAULT_PLANE_ICON;', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function buildSvgIcon(fill) {', 13, 10
               db '  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(', 13, 10
               db '    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\"><path d=\"M12 2L15 '
               db '10H22L16 14L18 22L12 18L6 22L8 14L2 10H9L12 2Z\" fill=\"" + fill + "\" stroke=\"#0a0e17\" stroke-width=\"1\"/></svg>"', 13, 10
               db '  );', 13, 10
               db '}', 13, 10
               db 'function buildAirportIcon() {', 13, 10
               db '  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(', 13, 10
               db '    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 20 20\"><circle cx=\"10\" '
               db 'cy=\"10\" r=\"8\" fill=\"none\" stroke=\"#4fc3f7\" stroke-width=\"1.5\"/><circle cx=\"10\" cy=\"10\" r=\"2\" '
               db 'fill=\"#4fc3f7\"/><line x1=\"10\" y1=\"2\" x2=\"10\" y2=\"6\" stroke=\"#4fc3f7\" stroke-width=\"1.2\"/><line x1=\"10\" '
               db 'y1=\"14\" x2=\"10\" y2=\"18\" stroke=\"#4fc3f7\" stroke-width=\"1.2\"/><line x1=\"2\" y1=\"10\" x2=\"6\" y2=\"10\" '
               db 'stroke=\"#4fc3f7\" stroke-width=\"1.2\"/><line x1=\"14\" y1=\"10\" x2=\"18\" y2=\"10\" stroke=\"#4fc3f7\" '
               db 'stroke-width=\"1.2\"/></svg>"', 13, 10
               db '  );', 13, 10
               db '}', 13, 10
               db 'function buildWaypointIcon() {', 13, 10
               db '  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(', 13, 10
               db '    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 12 12\"><polygon points=\"6,1 '
               db '11,11 1,11\" fill=\"none\" stroke=\"#78909c\" stroke-width=\"1.2\"/></svg>"', 13, 10
               db '  );', 13, 10
               db '}', 13, 10
               db 'function buildVortacIcon() {', 13, 10
               db '  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(', 13, 10
               db '    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 16 16\"><polygon points=\"8,1 '
               db '15,5 13,13 3,13 1,5\" fill=\"none\" stroke=\"#66bb6a\" stroke-width=\"1.2\"/><circle cx=\"8\" cy=\"8\" r=\"2\" '
               db 'fill=\"#66bb6a\"/></svg>"', 13, 10
               db '  );', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function haversineNM(lng1, lat1, lng2, lat2) {', 13, 10
               db '  const R = 3440.065;', 13, 10
               db '  const dLat = (lat2 - lat1) * Math.PI / 180;', 13, 10
               db '  const dLng = (lng2 - lng1) * Math.PI / 180;', 13, 10
               db '  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / '
               db '2) ** 2;', 13, 10
               db '  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));', 13, 10
               db '}', 13, 10
               db 'function computeBearing(lng1, lat1, lng2, lat2) {', 13, 10
               db '  const dLng = (lng2 - lng1) * Math.PI / 180;', 13, 10
               db '  const lat1r = lat1 * Math.PI / 180, lat2r = lat2 * Math.PI / 180;', 13, 10
               db '  const y = Math.sin(dLng) * Math.cos(lat2r);', 13, 10
               db '  const x = Math.cos(lat1r) * Math.sin(lat2r) - Math.sin(lat1r) * Math.cos(lat2r) * Math.cos(dLng);', 13, 10
               db '  return ((Math.atan2(y, x) * 180 / Math.PI) + 360) % 360;', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'let map = null;', 13, 10
               db 'let ready = false;', 13, 10
               db 'let showLabels = true;', 13, 10
               db 'let measureMode = false;', 13, 10
               db 'let measurePoints = [];', 13, 10
               db 'let selectedCallsign = null;', 13, 10
               db 'let aircraftState = {};', 13, 10
               db 'let lastUpdate = performance.now();', 13, 10
               db 13, 10
               db 'function loadImage(name, url, w, h, sdf) {', 13, 10
               db '  return new Promise((resolve) => {', 13, 10
               db '    const img = new Image(w, h);', 13, 10
               db '    img.onload = () => {', 13, 10
               db '      if (!map.hasImage(name)) map.addImage(name, img, { sdf: !!sdf });', 13, 10
               db '      resolve();', 13, 10
               db '    };', 13, 10
               db '    img.onerror = () => resolve();', 13, 10
               db '    img.src = url;', 13, 10
               db '  });', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function setVisibility(layer, vis) {', 13, 10
               db '  if (map.getLayer(layer)) map.setLayoutProperty(layer, "visibility", vis);', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function updateMeasureUi() {', 13, 10
               db '  const bar = document.getElementById("measure-bar");', 13, 10
               db '  if (!measureMode || measurePoints.length !== 2) {', 13, 10
               db '    bar.classList.add("hidden");', 13, 10
               db '    return;', 13, 10
               db '  }', 13, 10
               db '  const [a, b] = measurePoints;', 13, 10
               db '  document.getElementById("measure-dist").textContent = "↗ " + haversineNM(a.lng, a.lat, b.lng, b.lat).toFixed(1) + " '
               db 'NM";', 13, 10
               db '  document.getElementById("measure-brg").textContent = "BRG " + String(Math.round(computeBearing(a.lng, a.lat, b.lng, '
               db 'b.lat))).padStart(3, "0") + "°";', 13, 10
               db '  bar.classList.remove("hidden");', 13, 10
               db '  const lineSource = map.getSource("measure-line");', 13, 10
               db '  const pointSource = map.getSource("measure-points");', 13, 10
               db '  pointSource.setData({ type: "FeatureCollection", features: measurePoints.map(p => ({ type: "Feature", geometry: { '
               db 'type: "Point", coordinates: [p.lng, p.lat] }, properties: {} })) });', 13, 10
               db '  lineSource.setData({ type: "FeatureCollection", features: [{ type: "Feature", geometry: { type: "LineString", '
               db 'coordinates: [[a.lng, a.lat], [b.lng, b.lat]] }, properties: {} }] });', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function normalizeAircraftPayload(data) {', 13, 10
               db '  if (!data) return {};', 13, 10
               db '  if (data.aircraft && typeof data.aircraft === "object") data = data.aircraft;', 13, 10
               db '  const out = {};', 13, 10
               db '  if (Array.isArray(data)) {', 13, 10
               db '    for (const ac of data) {', 13, 10
               db '      const cs = ac.callsign || ac.Callsign || ac.name;', 13, 10
               db '      if (!cs) continue;', 13, 10
               db '      out[cs] = normalizeOneAircraft(cs, ac);', 13, 10
               db '    }', 13, 10
               db '    return out;', 13, 10
               db '  }', 13, 10
               db '  if (typeof data === "object") {', 13, 10
               db '    for (const [cs, ac] of Object.entries(data)) {', 13, 10
               db '      if (!ac || typeof ac !== "object") continue;', 13, 10
               db '      out[cs] = normalizeOneAircraft(cs, ac);', 13, 10
               db '    }', 13, 10
               db '  }', 13, 10
               db '  return out;', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function normalizeOneAircraft(cs, ac) {', 13, 10
               db '  const pos = ac.position || {};', 13, 10
               db '  return {', 13, 10
               db '    callsign: cs,', 13, 10
               db '    aircraftType: ac.aircraftType || ac.type || ac.AircraftType || "General Aviation",', 13, 10
               db '    heading: ac.heading || ac.Heading || 0,', 13, 10
               db '    altitude: ac.altitude || ac.Altitude || 0,', 13, 10
               db '    groundSpeed: ac.groundSpeed || ac.speed || ac.GroundSpeed || 0,', 13, 10
               db '    isOnGround: !!(ac.isOnGround || ac.onGround),', 13, 10
               db '    position: { x: pos.x || ac.x || 0, y: pos.y || ac.y || 0 }', 13, 10
               db '  };', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'async function fetchAircraft() {', 13, 10
               db '  const urls = [', 13, 10
               db '    "https://ws.awdevhardware.org/acft-data",', 13, 10
               db '    "https://24data.ptfs.app/acft-data"', 13, 10
               db '  ];', 13, 10
               db '  for (const url of urls) {', 13, 10
               db '    try {', 13, 10
               db '      const res = await fetch(url, { cache: "no-store" });', 13, 10
               db '      if (!res.ok) continue;', 13, 10
               db '      const json = await res.json();', 13, 10
               db '      const ac = normalizeAircraftPayload(json);', 13, 10
               db '      if (Object.keys(ac).length > 0) return ac;', 13, 10
               db '    } catch (_) {}', 13, 10
               db '  }', 13, 10
               db '  return null;', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function seedDemoAircraft() {', 13, 10
               db '  const demo = {};', 13, 10
               db '  const samples = [', 13, 10
               db '    { cs: "AAL427", type: "Boeing 737", x: -2925, y: 20082, hdg: 250, spd: 420, alt: 24000 },', 13, 10
               db '    { cs: "DAL109", type: "Airbus A320", x: -16272, y: 23655, hdg: 90, spd: 390, alt: 28000 },', 13, 10
               db '    { cs: "UAE12", type: "Airbus A380", x: 18105, y: -20409, hdg: 310, spd: 470, alt: 35000 },', 13, 10
               db '    { cs: "JAL81", type: "Boeing 787", x: -7368, y: -31953, hdg: 40, spd: 450, alt: 37000 },', 13, 10
               db '    { cs: "N17GA", type: "General Aviation", x: 5778, y: -4509, hdg: 180, spd: 140, alt: 6500 }', 13, 10
               db '  ];', 13, 10
               db '  for (const s of samples) {', 13, 10
               db '    demo[s.cs] = {', 13, 10
               db '      callsign: s.cs, aircraftType: s.type, heading: s.hdg, altitude: s.alt,', 13, 10
               db '      groundSpeed: s.spd, isOnGround: false, position: { x: s.x, y: s.y }', 13, 10
               db '    };', 13, 10
               db '  }', 13, 10
               db '  return demo;', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function renderAircraft() {', 13, 10
               db '  if (!ready) return;', 13, 10
               db '  const elapsed = (performance.now() - lastUpdate) / 1000;', 13, 10
               db '  const features = [];', 13, 10
               db '  for (const [cs, ac] of Object.entries(aircraftState)) {', 13, 10
               db '    let x = ac.position.x, y = ac.position.y;', 13, 10
               db '    if (!ac.isOnGround && (ac.groundSpeed || 0) > 5 && elapsed < 8) {', 13, 10
               db '      const hdg = ((ac.heading || 0) - 90) * DEG_TO_RAD;', 13, 10
               db '      const spd = (ac.groundSpeed || 0) * STUDS_PER_SEC;', 13, 10
               db '      x += Math.cos(hdg) * spd * elapsed;', 13, 10
               db '      y += Math.sin(hdg) * spd * elapsed;', 13, 10
               db '    }', 13, 10
               db '    const [lng, lat] = projectStudsToLngLat(x, y);', 13, 10
               db '    const isSelected = cs === selectedCallsign;', 13, 10
               db '    features.push({', 13, 10
               db '      type: "Feature",', 13, 10
               db '      geometry: { type: "Point", coordinates: [lng, lat] },', 13, 10
               db '      properties: {', 13, 10
               db '        callsign: cs,', 13, 10
               db '        icon: getPlaneIconName(ac.aircraftType || ""),', 13, 10
               db '        heading: ac.heading || 0,', 13, 10
               db '        label: showLabels ? cs : "",', 13, 10
               db '        isSelected: isSelected,', 13, 10
               db '        iconColor: isSelected ? "#22c55e" : "#ffffff",', 13, 10
               db '        textColor: isSelected ? "#22c55e" : "#94a3b8",', 13, 10
               db '        meta: (ac.aircraftType || "") + " · FL" + Math.round((ac.altitude || 0) / 100) + " · " + '
               db 'Math.round(ac.groundSpeed || 0) + "kt"', 13, 10
               db '      }', 13, 10
               db '    });', 13, 10
               db '  }', 13, 10
               db '  const src = map.getSource("aircraft");', 13, 10
               db '  if (src) src.setData({ type: "FeatureCollection", features: features });', 13, 10
               db '  document.getElementById("ac-count").textContent = features.length + " tracks";', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'async function refreshAircraft() {', 13, 10
               db '  const live = await fetchAircraft();', 13, 10
               db '  aircraftState = live || aircraftState;', 13, 10
               db '  if (!live && Object.keys(aircraftState).length === 0) aircraftState = seedDemoAircraft();', 13, 10
               db '  lastUpdate = performance.now();', 13, 10
               db '  renderAircraft();', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'function initMap() {', 13, 10
               db '  const center = projectStudsToLngLat(-1417, 17840);', 13, 10
               db '  map = new maplibregl.Map({', 13, 10
               db '    container: "map",', 13, 10
               db '    style: {', 13, 10
               db '      version: 8,', 13, 10
               db '      sources: {},', 13, 10
               db '      layers: [{ id: "background", type: "background", paint: { "background-color": "#0a0e17" } }],', 13, 10
               db '      glyphs: "https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf"', 13, 10
               db '    },', 13, 10
               db '    center: center,', 13, 10
               db '    zoom: 10,', 13, 10
               db '    maxZoom: 16,', 13, 10
               db '    minZoom: 6', 13, 10
               db '  });', 13, 10
               db 13, 10
               db '  map.on("load", async () => {', 13, 10
               db '    const iconPromises = [', 13, 10
               db '      loadImage("aircraft-icon", buildSvgIcon("#06b6d4"), 24, 24),', 13, 10
               db '      loadImage("airport-icon", buildAirportIcon(), 20, 20),', 13, 10
               db '      loadImage("waypoint-icon", buildWaypointIcon(), 12, 12),', 13, 10
               db '      loadImage("vortac-icon", buildVortacIcon(), 16, 16),', 13, 10
               db '      ...PLANE_ICON_FILES.map(f => loadImage("plane-" + f, "/Plane%20Icons/" + encodeURIComponent(f) + ".png", 48, 48, '
               db 'true))', 13, 10
               db '    ];', 13, 10
               db '    await Promise.all(iconPromises);', 13, 10
               db 13, 10
               db '    map.addSource("boundaries", {', 13, 10
               db '      type: "geojson",', 13, 10
               db '      data: {', 13, 10
               db '        type: "FeatureCollection",', 13, 10
               db '        features: BOUNDARIES.map(seg => ({', 13, 10
               db '          type: "Feature",', 13, 10
               db '          geometry: { type: "LineString", coordinates: seg.points.map(([x, y]) => projectStudsToLngLat(x, y)) },', 13, 10
               db '          properties: {}', 13, 10
               db '        }))', 13, 10
               db '      }', 13, 10
               db '    });', 13, 10
               db '    map.addLayer({ id: "boundary-lines", type: "line", source: "boundaries", paint: { "line-color": "#1e3a5f", '
               db '"line-width": 1, "line-opacity": 0.6 } });', 13, 10
               db 13, 10
               db '    map.addSource("waypoints", {', 13, 10
               db '      type: "geojson",', 13, 10
               db '      data: {', 13, 10
               db '        type: "FeatureCollection",', 13, 10
               db '        features: WAYPOINTS.map(wp => ({', 13, 10
               db '          type: "Feature",', 13, 10
               db '          geometry: { type: "Point", coordinates: projectStudsToLngLat(wp.x, wp.y) },', 13, 10
               db '          properties: { name: wp.name }', 13, 10
               db '        }))', 13, 10
               db '      }', 13, 10
               db '    });', 13, 10
               db '    map.addLayer({', 13, 10
               db '      id: "waypoints-layer", type: "symbol", source: "waypoints",', 13, 10
               db '      layout: {', 13, 10
               db '        "icon-image": "waypoint-icon", "icon-size": 0.8, "icon-allow-overlap": true,', 13, 10
               db '        "text-field": ["get", "name"], "text-font": ["Noto Sans Regular"], "text-size": 9,', 13, 10
               db '        "text-offset": [0, 1.2], "text-allow-overlap": false', 13, 10
               db '      },', 13, 10
               db '      paint: { "text-color": "#546e7a", "text-halo-color": "#0a0e17", "text-halo-width": 1 },', 13, 10
               db '      minzoom: 9', 13, 10
               db '    });', 13, 10
               db 13, 10
               db '    map.addSource("vortacs", {', 13, 10
               db '      type: "geojson",', 13, 10
               db '      data: {', 13, 10
               db '        type: "FeatureCollection",', 13, 10
               db '        features: VORTACS.map(v => ({', 13, 10
               db '          type: "Feature",', 13, 10
               db '          geometry: { type: "Point", coordinates: projectStudsToLngLat(v.x, v.y) },', 13, 10
               db '          properties: { label: v.freq ? (v.id + " " + v.freq) : v.id }', 13, 10
               db '        }))', 13, 10
               db '      }', 13, 10
               db '    });', 13, 10
               db '    map.addLayer({', 13, 10
               db '      id: "vortacs-layer", type: "symbol", source: "vortacs",', 13, 10
               db '      layout: {', 13, 10
               db '        "icon-image": "vortac-icon", "icon-size": 1, "icon-allow-overlap": true,', 13, 10
               db '        "text-field": ["get", "label"], "text-font": ["Noto Sans Regular"], "text-size": 9,', 13, 10
               db '        "text-offset": [0, 1.6], "text-allow-overlap": false', 13, 10
               db '      },', 13, 10
               db '      paint: { "text-color": "#66bb6a", "text-halo-color": "#0a0e17", "text-halo-width": 1 },', 13, 10
               db '      minzoom: 8', 13, 10
               db '    });', 13, 10
               db 13, 10
               db '    map.addSource("airports", {', 13, 10
               db '      type: "geojson",', 13, 10
               db '      data: {', 13, 10
               db '        type: "FeatureCollection",', 13, 10
               db '        features: AIRPORTS.map(ap => ({', 13, 10
               db '          type: "Feature",', 13, 10
               db '          geometry: { type: "Point", coordinates: projectStudsToLngLat(ap.x, ap.y) },', 13, 10
               db '          properties: { icao: ap.icao, name: ap.name, label: ap.icao + "\n" + ap.name }', 13, 10
               db '        }))', 13, 10
               db '      }', 13, 10
               db '    });', 13, 10
               db '    map.addLayer({', 13, 10
               db '      id: "airports-layer", type: "symbol", source: "airports",', 13, 10
               db '      layout: {', 13, 10
               db '        "icon-image": "airport-icon", "icon-size": 1.2, "icon-allow-overlap": true, "icon-ignore-placement": true,', 13, 10
               db '        "text-field": ["get", "label"], "text-font": ["Noto Sans Regular"], "text-size": 11,', 13, 10
               db '        "text-offset": [0, 2], "text-allow-overlap": true, "text-ignore-placement": true, "text-anchor": "top"', 13, 10
               db '      },', 13, 10
               db '      paint: { "text-color": "#4fc3f7", "text-halo-color": "#0a0e17", "text-halo-width": 2 }', 13, 10
               db '    });', 13, 10
               db 13, 10
               db '    map.addSource("aircraft", { type: "geojson", data: { type: "FeatureCollection", features: [] } });', 13, 10
               db '    map.addLayer({', 13, 10
               db '      id: "aircraft-layer", type: "symbol", source: "aircraft",', 13, 10
               db '      layout: {', 13, 10
               db '        "icon-image": ["coalesce", ["image", ["get", "icon"]], "aircraft-icon"],', 13, 10
               db '        "icon-size": ["case", ["get", "isSelected"], 1.3, 1],', 13, 10
               db '        "icon-rotate": ["get", "heading"], "icon-rotation-alignment": "map",', 13, 10
               db '        "icon-allow-overlap": true, "icon-ignore-placement": true,', 13, 10
               db '        "text-field": ["get", "label"], "text-font": ["Noto Sans Regular"], "text-size": 10,', 13, 10
               db '        "text-offset": [0, 1.6], "text-allow-overlap": true, "text-ignore-placement": true', 13, 10
               db '      },', 13, 10
               db '      paint: {', 13, 10
               db '        "icon-color": ["get", "iconColor"], "icon-halo-color": "#000000", "icon-halo-width": 1.5,', 13, 10
               db '        "text-color": ["get", "textColor"], "text-halo-color": "#0a0e17", "text-halo-width": 1', 13, 10
               db '      }', 13, 10
               db '    });', 13, 10
               db 13, 10
               db '    map.addSource("measure-line", { type: "geojson", data: { type: "FeatureCollection", features: [] } });', 13, 10
               db '    map.addLayer({ id: "measure-line-layer", type: "line", source: "measure-line", paint: { "line-color": "#f472b6", '
               db '"line-width": 2, "line-dasharray": [2, 2] } });', 13, 10
               db '    map.addSource("measure-points", { type: "geojson", data: { type: "FeatureCollection", features: [] } });', 13, 10
               db '    map.addLayer({ id: "measure-points-layer", type: "circle", source: "measure-points", paint: { "circle-radius": 5, '
               db '"circle-color": "#f472b6", "circle-stroke-width": 2, "circle-stroke-color": "#0a0e17" } });', 13, 10
               db 13, 10
               db '    ready = true;', 13, 10
               db '    aircraftState = seedDemoAircraft();', 13, 10
               db '    lastUpdate = performance.now();', 13, 10
               db '    renderAircraft();', 13, 10
               db '    refreshAircraft();', 13, 10
               db '    setInterval(refreshAircraft, 4000);', 13, 10
               db '  });', 13, 10
               db 13, 10
               db '  map.on("click", (e) => {', 13, 10
               db '    if (!measureMode) return;', 13, 10
               db '    const pt = { lng: e.lngLat.lng, lat: e.lngLat.lat };', 13, 10
               db '    measurePoints = measurePoints.length >= 2 ? [pt] : measurePoints.concat([pt]);', 13, 10
               db '    if (measurePoints.length < 2) {', 13, 10
               db '      map.getSource("measure-line").setData({ type: "FeatureCollection", features: [] });', 13, 10
               db '      map.getSource("measure-points").setData({', 13, 10
               db '        type: "FeatureCollection",', 13, 10
               db '        features: measurePoints.map(p => ({ type: "Feature", geometry: { type: "Point", coordinates: [p.lng, p.lat] }, '
               db 'properties: {} }))', 13, 10
               db '      });', 13, 10
               db '      document.getElementById("measure-bar").classList.add("hidden");', 13, 10
               db '    } else updateMeasureUi();', 13, 10
               db '  });', 13, 10
               db 13, 10
               db '  map.on("click", "aircraft-layer", (e) => {', 13, 10
               db '    if (measureMode) return;', 13, 10
               db '    const f = e.features && e.features[0];', 13, 10
               db '    if (!f) return;', 13, 10
               db '    selectedCallsign = f.properties.callsign;', 13, 10
               db '    document.getElementById("selected").classList.remove("hidden");', 13, 10
               db '    document.getElementById("sel-cs").textContent = selectedCallsign;', 13, 10
               db '    document.getElementById("sel-meta").textContent = f.properties.meta || "";', 13, 10
               db '    renderAircraft();', 13, 10
               db '  });', 13, 10
               db 13, 10
               db '  map.on("mouseenter", "aircraft-layer", () => { map.getCanvas().style.cursor = "pointer"; });', 13, 10
               db '  map.on("mouseleave", "aircraft-layer", () => { map.getCanvas().style.cursor = measureMode ? "crosshair" : ""; });', 13, 10
               db '}', 13, 10
               db 13, 10
               db 'document.getElementById("btn-labels").addEventListener("click", () => {', 13, 10
               db '  showLabels = !showLabels;', 13, 10
               db '  const btn = document.getElementById("btn-labels");', 13, 10
               db '  btn.classList.toggle("active", showLabels);', 13, 10
               db '  btn.textContent = showLabels ? "Fixes ON" : "Fixes OFF";', 13, 10
               db '  const vis = showLabels ? "visible" : "none";', 13, 10
               db '  setVisibility("waypoints-layer", vis);', 13, 10
               db '  setVisibility("vortacs-layer", vis);', 13, 10
               db '  renderAircraft();', 13, 10
               db '});', 13, 10
               db 13, 10
               db 'document.getElementById("btn-measure").addEventListener("click", () => {', 13, 10
               db '  measureMode = !measureMode;', 13, 10
               db '  measurePoints = [];', 13, 10
               db '  const btn = document.getElementById("btn-measure");', 13, 10
               db '  btn.classList.toggle("measure-on", measureMode);', 13, 10
               db '  btn.textContent = measureMode ? "Measure ON" : "Measure";', 13, 10
               db '  map.getCanvas().style.cursor = measureMode ? "crosshair" : "";', 13, 10
               db '  map.getSource("measure-line").setData({ type: "FeatureCollection", features: [] });', 13, 10
               db '  map.getSource("measure-points").setData({ type: "FeatureCollection", features: [] });', 13, 10
               db '  document.getElementById("measure-bar").classList.add("hidden");', 13, 10
               db '});', 13, 10
               db 13, 10
               db 'document.getElementById("btn-measure-clear").addEventListener("click", () => {', 13, 10
               db '  measurePoints = [];', 13, 10
               db '  map.getSource("measure-line").setData({ type: "FeatureCollection", features: [] });', 13, 10
               db '  map.getSource("measure-points").setData({ type: "FeatureCollection", features: [] });', 13, 10
               db '  document.getElementById("measure-bar").classList.add("hidden");', 13, 10
               db '});', 13, 10
               db 13, 10
               db 'initMap();', 13, 10
               db 'requestAnimationFrame(function tick() { renderAircraft(); requestAnimationFrame(tick); });', 13, 10
               db 13, 10
               db '</script>', 13, 10
               db '</body>', 13, 10
               db '</html>'
    radar_len equ $ - radar_page

section .text
    global radar_html

radar_html:
    lea rax, [radar_page]
    mov rdx, radar_len
    ret
