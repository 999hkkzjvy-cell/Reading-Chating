import { h } from './utils.js';

const LATAM_COUNTRIES = [
  { id: 'mx', isoNum: 484, name: '墨西哥', flag: '🇲🇽',
    authors: [
      { name: '奥克塔维奥·帕斯', en: 'Octavio Paz', bio: '1990年诺贝尔文学奖得主，墨西哥最伟大的诗人、散文家。作品融合超现实主义与拉美本土文化。', works: ['《太阳石》', '《孤独的迷宫》', '《弓与琴》'] },
      { name: '卡洛斯·富恩特斯', en: 'Carlos Fuentes', bio: '拉美文学爆炸核心人物，以实验性叙事探索墨西哥身份认同与历史。', works: ['《最明净的地区》', '《阿尔特米奥·克罗斯之死》', '《奥拉》'] },
      { name: '胡安·鲁尔福', en: 'Juan Rulfo', bio: '魔幻现实主义先驱，一生仅出版两部作品却影响深远，马尔克斯称其教会自己写作。', works: ['《佩德罗·巴拉莫》', '《燃烧的原野》'] }
    ] },
  { id: 'gt', isoNum: 320, name: '危地马拉', flag: '🇬🇹',
    authors: [
      { name: '米格尔·安赫尔·阿斯图里亚斯', en: 'Miguel Ángel Asturias', bio: '1967年诺贝尔文学奖得主，魔幻现实主义先驱，作品根植于玛雅文化与反独裁斗争。', works: ['《总统先生》', '《玉米人》', '《强风》'] }
    ] },
  { id: 'cu', isoNum: 192, name: '古巴', flag: '🇨🇺',
    authors: [
      { name: '阿莱霍·卡彭铁尔', en: 'Alejo Carpentier', bio: '魔幻现实主义奠基人，"神奇现实"理论的提出者，将巴洛克美学融入拉美叙事。', works: ['《人间王国》', '《消失的脚步》', '《光明世纪》'] },
      { name: '何塞·马蒂', en: 'José Martí', bio: '古巴民族英雄、现代主义诗歌先驱，以热血文字呼唤拉美独立与团结。', works: ['《伊斯马埃利约》', '《纯朴的诗》', '《我们的美洲》'] }
    ] },
  { id: 'ni', isoNum: 558, name: '尼加拉瓜', flag: '🇳🇮',
    authors: [
      { name: '鲁文·达里奥', en: 'Rubén Darío', bio: '拉美现代主义诗歌之父，革新西班牙语诗歌韵律与意象，影响遍及整个西语世界。', works: ['《蓝》', '《亵渎的散文》', '《生命与希望之歌》'] }
    ] },
  { id: 'co', isoNum: 170, name: '哥伦比亚', flag: '🇨🇴',
    authors: [
      { name: '加西亚·马尔克斯', en: 'Gabriel García Márquez', bio: '1982年诺贝尔文学奖得主，魔幻现实主义巅峰代表，二十世纪最伟大的小说家之一。', works: ['《百年孤独》', '《霍乱时期的爱情》', '《族长的秋天》'] },
      { name: '阿尔瓦罗·穆蒂斯', en: 'Álvaro Mutis', bio: '诗人、小说家，马尔克斯挚友，以航海史诗《马科洛尔的冒险》系列闻名。', works: ['《阿米尔巴尔》', '《伊洛娜随雨而至》'] }
    ] },
  { id: 've', isoNum: 862, name: '委内瑞拉', flag: '🇻🇪',
    authors: [
      { name: '罗慕洛·加列戈斯', en: 'Rómulo Gallegos', bio: '委内瑞拉最伟大的小说家，以描绘大草原与民族精神闻名，曾短暂担任总统。', works: ['《堂娜芭芭拉》', '《坎塔克拉罗》'] }
    ] },
  { id: 'ec', isoNum: 218, name: '厄瓜多尔', flag: '🇪🇨',
    authors: [
      { name: '豪尔赫·伊卡萨', en: 'Jorge Icaza', bio: '土著主义文学代表，以《瓦西蓬戈》揭露印第安人的悲惨命运，震撼拉美文坛。', works: ['《瓦西蓬戈》', '《混血儿》'] }
    ] },
  { id: 'pe', isoNum: 604, name: '秘鲁', flag: '🇵🇪',
    authors: [
      { name: '巴尔加斯·略萨', en: 'Mario Vargas Llosa', bio: '2010年诺贝尔文学奖得主，结构现实主义大师，以复调叙事探索权力与自由。', works: ['《城市与狗》', '《绿房子》', '《酒吧长谈》'] },
      { name: '塞萨尔·巴列霍', en: 'César Vallejo', bio: '二十世纪最伟大的西班牙语诗人之一，以先锋语言表达人类苦难与救赎。', works: ['《特里尔塞》', '《人类的诗篇》', '《黑色先驱》'] }
    ] },
  { id: 'bo', isoNum: 68, name: '玻利维亚', flag: '🇧🇴',
    authors: [
      { name: '海梅·萨恩斯', en: 'Jaime Sáenz', bio: '玻利维亚最重要的现代诗人，作品融合安第斯神秘主义与存在主义哲思。', works: ['《死亡之触》', '《访客》'] }
    ] },
  { id: 'cl', isoNum: 152, name: '智利', flag: '🇨🇱',
    authors: [
      { name: '巴勃罗·聂鲁达', en: 'Pablo Neruda', bio: '1971年诺贝尔文学奖得主，二十世纪最伟大的诗人之一，爱情与政治的诗篇传遍世界。', works: ['《二十首情诗和一首绝望的歌》', '《漫歌》', '《元素的颂歌》'] },
      { name: '加夫列拉·米斯特拉尔', en: 'Gabriela Mistral', bio: '1945年诺贝尔文学奖得主，拉美第一位诺奖作家，以深沉母性与悲悯情怀动人。', works: ['《绝望》', '《柔情》', '《塔拉》'] },
      { name: '罗贝托·波拉尼奥', en: 'Roberto Bolaño', bio: '后爆炸时代最具影响力的拉美作家，以《2666》重塑当代西语文学版图。', works: ['《2666》', '《荒野侦探》', '《遥远的星辰》'] }
    ] },
  { id: 'py', isoNum: 600, name: '巴拉圭', flag: '🇵🇾',
    authors: [
      { name: '奥古斯托·罗亚·巴斯托斯', en: 'Augusto Roa Bastos', bio: '巴拉圭最伟大的作家，塞万提斯奖得主，以《人子》三部曲书写巴拉圭民族史诗。', works: ['《人子》', '《我，至高无上者》'] }
    ] },
  { id: 'ar', isoNum: 32, name: '阿根廷', flag: '🇦🇷',
    authors: [
      { name: '豪尔赫·路易斯·博尔赫斯', en: 'Jorge Luis Borges', bio: '二十世纪最具原创性的作家之一，以迷宫、镜子、图书馆构建形而上学叙事宇宙。', works: ['《小径分岔的花园》', '《阿莱夫》', '《虚构集》'] },
      { name: '胡利奥·科塔萨尔', en: 'Julio Cortázar', bio: '拉美文学爆炸核心人物，以碎片化叙事打破现实主义传统，重新定义短篇小说。', works: ['《跳房子》', '《动物寓言集》', '《万火归一》'] },
      { name: '埃内斯托·萨瓦托', en: 'Ernesto Sabato', bio: '物理学家出身的小说家，以存在主义视角探索理性与疯狂的边界。', works: ['《隧道》', '《英雄与坟墓》'] }
    ] },
  { id: 'uy', isoNum: 858, name: '乌拉圭', flag: '🇺🇾',
    authors: [
      { name: '胡安·卡洛斯·奥内蒂', en: 'Juan Carlos Onetti', bio: '拉美心理小说先驱，以虚构城市圣玛利亚构建孤独绝望的叙事迷宫。', works: ['《造船厂》', '《短暂的生命》', '《收尸人》'] },
      { name: '马里奥·贝内德蒂', en: 'Mario Benedetti', bio: '乌拉圭最受爱戴的作家，以平实语言书写普通人生活、爱情与流亡。', works: ['《休战》', '《感谢火焰》'] }
    ] },
  { id: 'br', isoNum: 76, name: '巴西', flag: '🇧🇷',
    authors: [
      { name: '马查多·德·阿西斯', en: 'Machado de Assis', bio: '巴西文学之父，以冷峻讽刺与心理洞察开创拉美现实主义小说先河。', works: ['《布拉兹·库巴斯的死后回忆》', '《堂卡斯穆罗》'] },
      { name: '克拉丽丝·李斯佩克特', en: 'Clarice Lispector', bio: '二十世纪最重要的巴西作家之一，以独特内省风格探索存在与语言的边界。', works: ['《星辰时刻》', '《靠近狂野之心》'] },
      { name: '若热·亚马多', en: 'Jorge Amado', bio: '巴西最广为人知的作家，以热情奔放的笔触描绘巴伊亚的人情风土。', works: ['《加布里埃拉、丁香与肉桂》', '《弗洛尔姑娘和她的两个丈夫》'] }
    ] }
];

const defaultMapStyle = { fillColor: '#d9a87a', fillOpacity: 0.45, color: '#8b6914', weight: 1.5, opacity: 0.8 };
let latamMap = null;
let latamLayer = null;

function introPanelHtml() {
  return `
    <h2>🌎 拉丁美洲文学地图</h2>
    <div class="panel-intro">
      拉丁美洲是二十世纪世界文学的爆炸原点。从魔幻现实主义到结构现实主义，
      从博尔赫斯的迷宫到聂鲁达的情诗，这片大陆孕育了最富想象力的文学图景。<br><br>
      <strong>点击地图上的国家</strong>，发现那些改变了世界文学版图的作家与作品。
    </div>
    <div style="margin-top:var(--space-3);padding-top:var(--space-3);border-top:1px solid var(--color-border);">
      <div style="font-size:0.78rem;color:var(--color-text-3);margin-bottom:6px;">🏆 诺贝尔文学奖得主（拉美）</div>
      <div style="font-size:0.78rem;color:var(--color-text-2);line-height:1.8;">
        1945 · 🇨🇱 加夫列拉·米斯特拉尔<br>
        1967 · 🇬🇹 米格尔·阿斯图里亚斯<br>
        1971 · 🇨🇱 巴勃罗·聂鲁达<br>
        1982 · 🇨🇴 加西亚·马尔克斯<br>
        1990 · 🇲🇽 奥克塔维奥·帕斯<br>
        2010 · 🇵🇪 巴尔加斯·略萨
      </div>
    </div>
  `;
}

function resetLayerStyles() {
  if (!latamLayer) return;
  latamLayer.eachLayer(layer => {
    layer._selected = false;
    layer.setStyle(defaultMapStyle);
  });
}

export function renderLatamPage() {
  const tagsHtml = LATAM_COUNTRIES.map(c =>
    `<span class="latam-tag" data-country="${c.id}">${c.flag} ${c.name}</span>`
  ).join('');

  return `
    <div class="container section">
      <div class="page-header">
        <h1>西语文学专区</h1>
        <div class="subtitle">拉丁美洲文学地图 · 探索西语世界的文学瑰宝</div>
      </div>

      <div class="latam-layout">
        <div class="latam-map-wrap" id="latam-map-wrap">
          <div id="latam-leaflet-map" style="width:100%;height:550px;border-radius:var(--radius-md);border:1px solid var(--color-border);box-shadow:var(--shadow-sm);"></div>
        </div>
        <div class="latam-panel" id="latam-panel">
          ${introPanelHtml()}
        </div>
      </div>

      <div class="latam-tags" id="latam-tags">
        ${tagsHtml}
      </div>
    </div>`;
}

export function renderLatamPanel(countryId) {
  const panel = document.getElementById('latam-panel');
  if (!panel) return;

  document.querySelectorAll('.latam-tag').forEach(t => t.classList.remove('active'));

  if (!countryId) {
    panel.innerHTML = introPanelHtml();
    resetLayerStyles();
    return;
  }

  const country = LATAM_COUNTRIES.find(c => c.id === countryId);
  if (!country) return;

  const tagEl = document.querySelector(`.latam-tag[data-country="${countryId}"]`);
  if (tagEl) tagEl.classList.add('active');

  if (latamLayer) {
    resetLayerStyles();
    latamLayer.eachLayer(layer => {
      if (layer.feature && layer.feature.properties.id === countryId) {
        layer._selected = true;
        layer.setStyle({ fillColor: '#a46533', fillOpacity: 0.7, weight: 3, color: '#8b4a2a' });
        layer.bringToFront();
        if (layer._map) {
          layer._map.fitBounds(layer.getBounds(), { padding: [30, 30], maxZoom: 6 });
        }
      }
    });
  }

  const authorsHtml = country.authors.map(a => `
    <div class="latam-author-card">
      <div class="author-name"><span class="icon">✍️</span>${h(a.name)}<span style="font-weight:400;font-size:0.75rem;color:var(--color-text-3);margin-left:4px;">${h(a.en)}</span></div>
      <div class="author-bio">${h(a.bio)}</div>
      <div class="author-works">${a.works.map(w => `<span class="work-tag">📖 ${h(w)}</span>`).join('')}</div>
    </div>
  `).join('');

  panel.innerHTML = `
    <h2>📍 ${h(country.name)}</h2>
    <div class="panel-intro">共 ${country.authors.length} 位代表作家</div>
    ${authorsHtml}
    <button class="btn btn-sm btn-outline" style="margin-top:var(--space-2);" id="btn-latam-back">← 返回总览</button>
  `;
}

export async function initLatamMap() {
  const mapEl = document.getElementById('latam-leaflet-map');
  if (!mapEl) return;

  if (typeof L === 'undefined') {
    await Promise.all([
      new Promise((ok, fail) => { const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = 'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.css'; l.onload = ok; l.onerror = fail; document.head.appendChild(l); }),
      new Promise((ok, fail) => { const s = document.createElement('script'); s.src = 'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.js'; s.onload = ok; s.onerror = fail; document.head.appendChild(s); }),
      new Promise((ok, fail) => { const s = document.createElement('script'); s.src = 'https://cdn.jsdelivr.net/npm/topojson-client@3'; s.onload = ok; s.onerror = fail; document.head.appendChild(s); })
    ]);
    await new Promise(r => setTimeout(r, 100));
  }

  if (latamMap) {
    latamMap.remove();
    latamMap = null;
    latamLayer = null;
  }

  latamMap = L.map(mapEl, {
    center: [-15, -65],
    zoom: 3,
    minZoom: 3,
    maxZoom: 8,
    zoomControl: true,
    scrollWheelZoom: true,
    maxBounds: [[15, -120], [-60, -30]],
    maxBoundsViscosity: 0.5
  });

  L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> &copy; <a href="https://carto.com/">CARTO</a>',
    subdomains: 'abcd',
    maxZoom: 19
  }).addTo(latamMap);

  const isoNumSet = new Set(LATAM_COUNTRIES.map(c => c.isoNum));
  try {
    const resp = await fetch('https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json');
    if (!resp.ok) throw new Error('TopoJSON fetch failed');
    const world = await resp.json();
    const topo = window.topojson || globalThis.topojson;
    if (!topo) throw new Error('topojson-client not loaded');
    const geojson = topo.feature(world, world.objects.countries);

    geojson.features = geojson.features
      .filter(f => isoNumSet.has(parseInt(f.id, 10)))
      .map(f => {
        const c = LATAM_COUNTRIES.find(x => x.isoNum === parseInt(f.id, 10));
        if (c) f.properties = { id: c.id, name: c.name, authors: c.authors };
        return f;
      });

    latamLayer = L.geoJSON(geojson, {
      style: () => defaultMapStyle,
      onEachFeature: (feature, layer) => {
        layer.on({
          mouseover: e => {
            const lyr = e.target;
            if (!lyr._selected) {
              lyr.setStyle({ fillColor: '#c17d4b', fillOpacity: 0.7, weight: 2.5, color: '#6b3a1f' });
            }
            lyr.bringToFront();
          },
          mouseout: e => {
            const lyr = e.target;
            if (!lyr._selected) {
              lyr.setStyle(defaultMapStyle);
            }
          },
          click: () => {
            renderLatamPanel(feature.properties.id);
          }
        });
      }
    }).addTo(latamMap);
  } catch (err) {
    console.error('Failed to load map data:', err);
    mapEl.innerHTML = '<div style="padding:20px;text-align:center;color:var(--color-danger);">地图数据加载失败：' + (err.message || '未知错误') + '<br><small>请检查网络后刷新重试</small></div>';
  }
}

export function bindLatamEvents() {
  document.addEventListener('click', e => {
    const backBtn = e.target.closest('#btn-latam-back');
    if (backBtn) {
      renderLatamPanel(null);
      return;
    }

    const countryTag = e.target.closest('.latam-tag');
    if (!countryTag) return;

    const countryId = countryTag.dataset.country;
    if (latamLayer) {
      let found = false;
      latamLayer.eachLayer(layer => {
        if (layer.feature && layer.feature.properties.id === countryId) {
          found = true;
          layer.fire('click');
        }
      });
      if (!found) renderLatamPanel(countryId);
    } else {
      renderLatamPanel(countryId);
    }
  });
}
