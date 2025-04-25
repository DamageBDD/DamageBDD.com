import * as sk from "./sidekick.js";
var address;
var logged_in = false;
var recipient = "damagebdd.chain";

function connect(logger) {
    return sk.connect(

        'ske-connect-1',
        {name: 'damagebdd.com',
         version: 1},
        sk.TIMEOUT_DEF_CONNECT_MS,
        "failed to connect to wallet",
        logger
    );
}
async function connectButton() {
    let logger = sk.cl();

    await connect(logger);
    let wallet_info = await sk.address(
        'ske-address-1',
        {type: 'subscribe',
         value: 'connected'},
        1000,
        "failed to address to wallet",
        logger
    );
    if (!wallet_info.ok){
        console.log("wallet info:"+ wallet_info);
        if(wallet_info.error.code == 420){
            document.getElementById("connect-status").innerHTML = "Please install <a href='https://chrome.google.com/webstore/detail/superhero/mnhmmkepfddpifjkamaligfeemcbhdne'>superhero wallet</a> to connect" ;
        }else{
            document.getElementById("connect-status").innerHTML = "Error connecting wallet " + wallet_info.error.message;
        }
        return;
    }else{
        document.getElementById("connect-status").innerHTML = "";
    }

    let maybe_address = Object.keys(wallet_info.result.address.current)[0];
    if (maybe_address === undefined) return;

    address = maybe_address;
    logged_in = true;
	document.getElementById("connect-button").disabled = true;
	document.getElementById("connect-button").style.display = 'none';
	const buyBtn = document.getElementById("buy-button");
    buyBtn.disabled = false;
	buyBtn.textContent = `💸Buy Tokens for ${address}`;
}
async function buyDamage() {
    let logger = sk.cl();
    const amount = parseInt(document.getElementById("damage-amount").value);

    if (isNaN(amount) || amount <= 0) {
        alert("Enter a valid amount");
        return;
    }

    const msg = JSON.stringify({amount, date:`${Date.now()}`});
    //const sigData = await sk.msg_sign(msg); // Sidekick signs message
    let sigData = await sk.msg_sign('sk-msg-sign-1', address, msg, sk.TIMEOUT_DEF_MSG_SIGN_MS, 'message signing took too long', logger);
    console.log('signed message:', sigData);

    const res = await fetch("/tx/", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            message: msg,
            signature: sigData.result.signature,
            pubkey: address
        })
    });

    const data = await res.json();
    if (!data.payment_request) throw new Error("No invoice returned");

    // Optionally auto-pay
    // const tx = await sk.pay(data.payment_request);

    // Show QR
    const qrCanvas = document.getElementById("lnqr");
    qrCanvas.innerHTML = "";
    new QRCode(qrCanvas, {
        text: data.payment_request,
        width: 300,
        height: 300,
    });

    alert("✅ Invoice ready.");
}
window.addEventListener('DOMContentLoaded', () => {
    const container = document.createElement('div');
    container.className = 'fire-button-container';

    const connectBtn = document.createElement('button');
	connectBtn.id = "connect-button";
    connectBtn.textContent = 'Connect Wallet';
    connectBtn.onclick = connectWalletSmart1;
	connectBtn.disabled = false;

    const buyBtn = document.createElement('button');
	buyBtn.id = "buy-button";
    buyBtn.textContent = '🔨 Buy Damage Tokens';
    buyBtn.disabled = true;
	buyBtn.onclick = buyDamage;

    container.appendChild(connectBtn);
    container.appendChild(buyBtn);
    document.getElementById("damage-wallet").appendChild(container);
    checkWalletAddress();
});


document.addEventListener("DOMContentLoaded", function () {
    const buyButton = document.getElementById("buy-button");
    if (buyButton) {
        buyButton.addEventListener("click", function () {
            const receiver = "ak_2abc..."; // replace with real Aeternity address
            const amount = 10; // amount in AE
            const url = `https://superhero.com/#/transfer?receiver=${receiver}&amount=${amount}`;
            window.location.href = url;
        });
    }
    connectButton();
});
function adjustAmount(delta) {
    const input = document.getElementById("damage-amount");
    const value = parseInt(input.value) || 0;
    input.value = Math.max(1, value + delta);
}

function setAmount(amount) {
    document.getElementById("damage-amount").value = amount;
}

document.addEventListener("DOMContentLoaded", () => {
    document.getElementById("btn-minus").addEventListener("click", () => adjustAmount(-100));
    document.getElementById("btn-plus").addEventListener("click", () => adjustAmount(100));

    document.querySelectorAll(".preset-amount").forEach(button => {
        button.addEventListener("click", () => {
            const amount = parseInt(button.dataset.amount);
            setAmount(amount);
        });
    });
});

// Superhero Wallet Integration Utilities

function encodeParams(params) {
    return Object.entries(params)
        .map(([key, val]) => `${encodeURIComponent(key)}=${encodeURIComponent(val)}`)
        .join("&");
}

export function connectWallet(successURL, cancelURL) {
    const params = {
        "x-success": successURL + "?address={address}&networkId={networkId}",
        "x-cancel": cancelURL
    };
    window.location.href = `https://wallet.superhero.com/address?${encodeParams(params)}`;
}

export function signMessage(message, successURL, cancelURL, encoding = "hex") {
    const params = {
        message,
        encoding,
        "x-success": `${successURL}?signature={signature}&address={address}`,
        "x-cancel": cancelURL
    };
    window.location.href = `https://wallet.superhero.com/sign-message?${encodeParams(params)}`;
}

export function signTransaction(transaction, networkId, successURL, cancelURL, broadcast = true) {
    const params = {
        transaction,
        networkId,
        broadcast: broadcast.toString(),
        "x-success": `${successURL}?transaction-hash={transaction-hash}`,
        "x-cancel": cancelURL
    };
    window.location.href = `https://wallet.superhero.com/sign-transaction?${encodeParams(params)}`;
}

export function signJWT(payload, successURL, cancelURL) {
    const params = {
        payload,
        "x-success": `${successURL}?signed-payload={signed-payload}&address={address}`,
        "x-cancel": cancelURL
    };
    window.location.href = `https://wallet.superhero.com/sign-jwt?${encodeParams(params)}`;
}



function connectWalletSmart1(){
    connectWalletSmart(
        "https://staging.damagebdd.com/use",
        "https://staging.damagebdd.com/use"
    );
}
// Usage:
// connectWallet('https://yourapp.com/success', 'https://yourapp.com/cancel')
// signMessage('hello', 'https://yourapp.com/msg-ok', 'https://yourapp.com/msg-fail')
function isMobileDevice() {
    return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}
function connectWalletSmart(successURL, cancelURL) {
    if (isMobileDevice()) {
        // Use Superhero mobile wallet deep link
        connectWallet(successURL, cancelURL);
    } else {
        // Use Sidekick browser wallet connection
        connectButton();
    }
}
function signMessageSmart(message, successURL, cancelURL) {
    if (isMobileDevice()) {
        signMessage(message, successURL, cancelURL);
    } else {
        sk.signMessage(message).then(({ signature, address }) => {
            window.location.href = `${successURL}?signature=${signature}&address=${address}`;
        }).catch(() => {
            window.location.href = cancelURL;
        });
    }
}
function checkWalletAddress(required = true) {
    const params = new URLSearchParams(window.location.search);
    const user_address = params.get("address");

    if (user_address) {
        console.log("✅ Wallet address found:", address);
	    const buyBtn = document.getElementById("buy-button");
        buyBtn.disabled = false;
	    buyBtn.textContent = `💸Buy Tokens for ${user_address}`;
        return address;
    }
    return null;
}
