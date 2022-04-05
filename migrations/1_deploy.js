const IdoSale = artifacts.require("IdoSale");

module.exports = function (deployer) {
  var ts = Math.round((new Date()).getTime() / 1000);
  deployer.deploy(IdoSale, "0xfac40DD9A8B8E25163D78A9016D1D805a34CD3e0", ts, ts + 3600);
};
