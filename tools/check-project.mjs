import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const jsonFiles = execFileSync('rg', ['--files', '-g', '*.json', '-g', '*.json5'], {
  encoding: 'utf8'
}).trim().split('\n').filter(Boolean);

for (const file of jsonFiles) {
  JSON.parse(readFileSync(file, 'utf8'));
}

const rootProfile = JSON.parse(readFileSync('build-profile.json5', 'utf8'));
const product = rootProfile.app.products.find((candidate) => candidate.name === 'default');
if (!product) {
  throw new Error('default product is missing');
}
if (product.compatibleSdkVersion !== '6.0.0(20)') {
  throw new Error('minimum supported SDK must remain HarmonyOS 6.0.0 / API 20');
}
if (product.targetSdkVersion !== '6.1.1(24)') {
  throw new Error('target SDK must remain HarmonyOS 6.1.1 / API 24 during M0');
}

const moduleProfile = JSON.parse(readFileSync('entry/src/main/module.json5', 'utf8'));
const deviceTypes = moduleProfile.module.deviceTypes;
for (const required of ['default', '2in1']) {
  if (!deviceTypes.includes(required)) {
    throw new Error(`required device type is missing: ${required}`);
  }
}

const vpnAbility = moduleProfile.module.extensionAbilities.find(
  (ability) => ability.name === 'ClashVpnExtensionAbility'
);
if (!vpnAbility || vpnAbility.type !== 'vpn' || vpnAbility.exported !== false) {
  throw new Error('private VPN Extension declaration is invalid');
}

console.log(`PASS: ${jsonFiles.length} JSON/JSON5 files and M0 invariants validated`);
