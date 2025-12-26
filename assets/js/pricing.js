
(function(window, document, undefined) {
	let lastDamageUSDT = null;
	let lastBtcUSDT = null;

	const numberFmt = (n, max=8) => {
		try {
			return new Intl.NumberFormat(undefined, { maximumFractionDigits: max }).format(n);
		} catch {
			return n.toLocaleString(undefined, { maximumFractionDigits: max });
		}
	};

	async function fetchJson(url) {
		const res = await fetch(url, { mode: 'cors' });
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
		return res.json();
	}

	async function fetchCoinstoreDamageAndBtc() {
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
		lastDamageUSDT = dmg;
		lastBtcUSDT = btc;
		return [dmg, btc];
	}

	function satsFromUsd(usd, btc_usdt) {
		return (usd * 1e8) / btc_usdt;
	}

	function convert(value, from, to) {
		if (lastDamageUSDT == null || lastBtcUSDT == null) return null;
		const dmg = lastDamageUSDT;
		const btc = lastBtcUSDT;
		const toUSDT = (val, what) => {
			if (what === 'DAMAGE') return val * dmg;
			if (what === 'USDT') return val;
			if (what === 'BTC') return val * btc;
			return NaN;
		};
		const fromUSDT = (usd, what) => {
			if (what === 'DAMAGE') return usd / dmg;
			if (what === 'USDT') return usd;
			if (what === 'BTC') return usd / btc;
			return NaN;
		};
		const usd = toUSDT(value, from);
		return fromUSDT(usd, to);
	}

	function bindConverter() {
		const amount = document.getElementById('conv-amount');
		const fromSel = document.getElementById('conv-from');
		const toSel   = document.getElementById('conv-to');
		const out     = document.getElementById('conv-output');
		const satsOut = document.getElementById('conv-output-sats');

		function recalcOnce() {
			if (!amount || !fromSel || !toSel || !out) return;
			const v = parseFloat(amount.value);
			if (Number.isNaN(v)) { out.textContent = '—'; if (satsOut) satsOut.textContent = '—'; return; }
			const res = convert(v, fromSel.value, toSel.value);
			if (res == null) { out.textContent = '…'; return; }
			out.textContent = numberFmt(res, toSel.value === 'BTC' ? 8 : 6) + ' ' + toSel.value;
			// also show sats for convenience
			if (satsOut) {
				let usd;
				if (toSel.value === 'USDT') usd = res;
				else if (toSel.value === 'DAMAGE') usd = res * lastDamageUSDT;
				else if (toSel.value === 'BTC') usd = res * lastBtcUSDT;
				else usd = NaN;
				const sats = satsFromUsd(usd, lastBtcUSDT);
				satsOut.textContent = Number.isFinite(sats) ? numberFmt(sats, 2) + ' sats' : '—';
			}
		}

		['input','change'].forEach(evt => {
			if (amount) amount.addEventListener(evt, recalcOnce);
			if (fromSel) fromSel.addEventListener(evt, recalcOnce);
			if (toSel) toSel.addEventListener(evt, recalcOnce);
		});

		return recalcOnce;
	}

	function updatePricingTable() {
		const status = document.querySelector('#pricing-status');
		const dmgCell = document.querySelector('#damage-usdt');
		const btcCell = document.querySelector('#btc-usdt');

		const dmgUSDT = lastDamageUSDT;
		const btcUSDT = lastBtcUSDT;
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
		if (status) status.textContent = 'Prices live from Coinstore • Last update: ' + ts;
	}

	let pendingConverterRecalc = null;

	async function tick() {
		try {
			const [dmgUSDT, btcUSDT] = await fetchCoinstoreDamageAndBtc();
			lastDamageUSDT = dmgUSDT;
			lastBtcUSDT = btcUSDT;
			updatePricingTable();
			if (typeof pendingConverterRecalc === 'function') pendingConverterRecalc();
		} catch (e) {
			const status = document.querySelector('#pricing-status');
			if (status) status.textContent = 'Price fetch failed from Coinstore.';
			console.warn(e);
		}
	}

	document.addEventListener("DOMContentLoaded", async function() {
		pendingConverterRecalc = bindConverter();
		tick();
		setInterval(tick, 60000);
	});

})(window, document, undefined);
