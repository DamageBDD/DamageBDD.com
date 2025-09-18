
(async function () {
  const numberFmt = (n) => {
    try {
      return new Intl.NumberFormat(undefined, { maximumFractionDigits: 8 }).format(n);
    } catch {
      return n.toLocaleString(undefined, { maximumFractionDigits: 8 });
    }
  };

  async function fetchJson(url) {
    const res = await fetch(url, { mode: 'cors' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  async function fetchCoinstoreDamageAndBtc() {
    // Coinstore REST: GET /v1/ticker/price?symbol=damageusdt,btcusdt
    const base = 'https://api.coinstore.com/api';
    const url = `${base}/v1/ticker/price?symbol=damageusdt,btcusdt`;
    const j = await fetchJson(url);
    if (!(j && (j.code === 0 || j.code === '0') && Array.isArray(j.data))) {
      throw new Error('Unexpected Coinstore response');
    }
    const map = new Map();
    j.data.forEach(row => {
      if (!row || !row.symbol) return;
      const sym = String(row.symbol).toLowerCase();
      const price = parseFloat(row.price);
      if (!Number.isNaN(price)) map.set(sym, price);
    });
    const dmg = map.get('damageusdt');
    const btc = map.get('btcusdt');
    if (!(dmg && btc)) throw new Error('Missing DAMAGE or BTC price from Coinstore');
    return [dmg, btc];
  }

  function satsFromUsd(usd, btc_usdt) {
    return (usd * 1e8) / btc_usdt;
  }

  async function recalc() {
    const status = document.querySelector('#pricing-status');
    const dmgCell = document.querySelector('#damage-usdt');
    const btcCell = document.querySelector('#btc-usdt');
    try {
      status.textContent = 'Updating prices…';
      const [dmgUSDT, btcUSDT] = await fetchCoinstoreDamageAndBtc();
      if (dmgCell) dmgCell.textContent = numberFmt(dmgUSDT);
      if (btcCell) btcCell.textContent = numberFmt(btcUSDT);

      document.querySelectorAll('[data-damage]').forEach(row => {
        const qty = parseFloat(row.getAttribute('data-damage'));
        if (Number.isNaN(qty) || qty <= 0) return;
        const usd = dmgUSDT * qty;
        const sats = satsFromUsd(usd, btcUSDT);

        const dmgSpan = row.querySelector('[data-price="damage"]');
        const usdSpan = row.querySelector('[data-price="usd"]');
        const satsSpan = row.querySelector('[data-price="sats"]');

        if (dmgSpan) dmgSpan.textContent = numberFmt(qty) + ' DAMAGE';
        if (usdSpan) usdSpan.textContent = '$' + numberFmt(usd);
        if (satsSpan) satsSpan.textContent = numberFmt(sats) + ' sats';
      });

      const ts = new Date().toLocaleString();
      status.textContent = 'Prices live from Coinstore • Last update: ' + ts;
    } catch (e) {
      status.textContent = 'Price fetch failed from Coinstore.';
      console.warn(e);
    }
  }

  recalc();
  setInterval(recalc, 60000);
})();
