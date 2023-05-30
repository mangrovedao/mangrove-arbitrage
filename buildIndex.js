/* ***** Mangrove tooling script ********* *
This script dynamically creates an index.js file for the dist directory of mangrove-core.

For instance, if the `dist/mangrove-abis` directory contains `Mangrove.json` and
`Maker.json`, it will include the following in `index.js`:

    exports.abis = {};
    exports.abis.Mangrove = require('mangrove-abis/Mangrove.json');
    exports.abis.Maker = require('mangrove-abis/Maker.json');

*/

const fs = require("fs");
const path = require("path");

const exportAllIn = (exportName, dir) => {
  const lines = [];
  lines.push(`exports.${exportName} = {};`);

  for (const fileName of fs.readdirSync(`${dir}`)) {
    const parsed = path.parse(fileName);
    lines.push(
      `exports.${exportName}['${parsed.name}'] = require("./${dir}/${fileName}");`
    );
  }
  return lines.join("\n");
};

const indexLines = [];
indexLines.push("// DO NOT MODIFY -- GENERATED BY buildIndex.js");
indexLines.push(exportAllIn("MgvArbitrage", "out/MgvArbitrage.sol"));
indexLines.push(exportAllIn("addresses.deployed", "addresses/deployed"));

fs.writeFileSync("index.js", indexLines.join("\n"));

console.log("Wrote index.js");
