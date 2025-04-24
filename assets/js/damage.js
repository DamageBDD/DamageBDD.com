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
    alert(`🔨 Tokens Bought! TX Hash: ${tx.hash}`);
}
window.addEventListener('DOMContentLoaded', () => {
  const container = document.createElement('div');
  container.className = 'fire-button-container';

  const connectBtn = document.createElement('button');
	connectBtn.id = "connect-button";
  connectBtn.textContent = 'Connect Wallet';
  connectBtn.onclick = connectButton;
	connectBtn.disabled = false;

  const buyBtn = document.createElement('button');
	buyBtn.id = "buy-button";
  buyBtn.textContent = '🔨 Buy Damage Tokens';
  buyBtn.disabled = true;
	buyBtn.onclick = buyDamage;

  container.appendChild(connectBtn);
  container.appendChild(buyBtn);
  document.getElementById("damage-wallet").appendChild(container);
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
});
