import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const EXPECTED_HEADER_PAYLOAD_SHA256 = "58f9c44fff04aca7465eaa3b75200362932cbdfd87552653c638c51451948254";
const EXPECTED_BODY_SHA256 = "817f05b421f84531fbf23648dc5e7394090d0d919959939b3073acf3eb9efeca";
const EXPECTED_PATCHED_BODY_SHA256 = "23847c75b72174e16a0764ebbd0f66b0ab2e55c9cc19418ccdcd7a15ebfb1335";
const EXPECTED_PACKED_SHA256 = "fb6f7333374345f131fefb1ac114947bdb9c91816f1ade2218cf30211d403acc";
const PLAYER_COUNT_SEQUENCE_OFFSET = 0xa3fb + 49 * 4;
const ORIGINAL_SEQUENCE = Buffer.from("190505d51000000002050202", "hex");
const PATCHED_SEQUENCE = Buffer.from("130504002205050022050500", "hex");

function getArgument(name) {
    const index = process.argv.indexOf(`--${name}`);
    if (index === -1 || !process.argv[index + 1]) throw new Error(`Missing --${name}`);
    return path.resolve(process.argv[index + 1]);
}

function sha256(data) {
    return crypto.createHash("sha256").update(data).digest("hex");
}

function crc32c(data) {
    let crc = 0xffffffff;
    for (const byte of data) {
        crc ^= byte;
        for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0x82f63b78 : 0);
    }
    return (~crc) >>> 0;
}

function u32(value) {
    const result = Buffer.alloc(4);
    result.writeUInt32LE(value >>> 0);
    return result;
}

function packUncompressed(header, body) {
    const prefix = Buffer.from([0x53, 0x48, 0x43, 0x43, 0x1f, 0, 0, 0]);
    const contentHash = crypto.createHash("md5").update(prefix).update(header.subarray(16)).update(body).digest();
    const withoutCrc = Buffer.concat([
        prefix,
        Buffer.from([0]), u32(header.length), u32(header.length), contentHash, header.subarray(16),
        Buffer.from([0]), u32(body.length), u32(body.length), body,
        Buffer.from([0, 0, 0, 0, 0, 0, 0, 0, 0, 0x52])
    ]);
    return { contentHash, packed: Buffer.concat([withoutCrc, u32(crc32c(withoutCrc))]) };
}

const header = fs.readFileSync(getArgument("header"));
const sourceBody = fs.readFileSync(getArgument("body"));
const outputDirectory = getArgument("output-directory");
if (header.length < 16 || sha256(header.subarray(16)) !== EXPECTED_HEADER_PAYLOAD_SHA256) {
    throw new Error(`Unsupported LotusGameRules header SHA-256: ${sha256(header)}`);
}
const sourceBodySha256 = sha256(sourceBody);
if (![EXPECTED_BODY_SHA256, EXPECTED_PATCHED_BODY_SHA256].includes(sourceBodySha256)) {
    throw new Error(`Unsupported LotusGameRules body SHA-256: ${sourceBodySha256}`);
}
const sequence = sourceBody.subarray(PLAYER_COUNT_SEQUENCE_OFFSET, PLAYER_COUNT_SEQUENCE_OFFSET + 12);
const patchedBody = Buffer.from(sourceBody);
if (sourceBodySha256 === EXPECTED_BODY_SHA256 && sequence.equals(ORIGINAL_SEQUENCE)) {
    PATCHED_SEQUENCE.copy(patchedBody, PLAYER_COUNT_SEQUENCE_OFFSET);
} else if (sourceBodySha256 !== EXPECTED_PATCHED_BODY_SHA256 || !sequence.equals(PATCHED_SEQUENCE)) {
    throw new Error("SpawnEliteAlertDrone bytecode does not match the verified original or patched instructions");
}
if (sha256(patchedBody) !== EXPECTED_PATCHED_BODY_SHA256) throw new Error("Patched Lua body verification failed");

const { contentHash, packed } = packUncompressed(header, patchedBody);
if (sha256(packed) !== EXPECTED_PACKED_SHA256) {
    throw new Error(`Generated replacement SHA-256 is unexpected: ${sha256(packed)}`);
}
const encodedHash = contentHash.toString("base64").replaceAll("/", "-").replace(/=+$/, "");
const fileName = `LotusGameRules.lua!75_${encodedHash}`;
fs.mkdirSync(outputDirectory, { recursive: true });
const outputPath = path.join(outputDirectory, fileName);
fs.writeFileSync(outputPath, packed);
process.stdout.write(JSON.stringify({ fileName, outputPath, packedSha256: sha256(packed) }));
