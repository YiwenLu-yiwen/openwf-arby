import fs from "node:fs";
import path from "node:path";

const serverRoot = path.resolve(process.argv[2] ?? "");
const checkOnly = process.argv.includes("--check");
if (!serverRoot || !fs.existsSync(path.join(serverRoot, "package.json"))) {
    throw new Error("SpaceNinjaServer root was not found.");
}

const marker = "ARBITRATION4_SELECTOR_V2";
const legacyMarker = "ARBITRATION4_SELECTOR_V1";
const paths = {
    config: path.join(serverRoot, "src", "services", "configService.ts"),
    world: path.join(serverRoot, "src", "services", "worldStateService.ts"),
    html: path.join(serverRoot, "static", "webui", "index.html"),
    script: path.join(serverRoot, "static", "webui", "script.js")
};

for (const [name, file] of Object.entries(paths)) {
    if (!fs.existsSync(file)) throw new Error(`Required ${name} file was not found: ${file}`);
}

function replaceExactlyOnce(source, search, replacement, label) {
    const first = source.indexOf(search);
    if (first === -1) throw new Error(`Compatible anchor was not found in ${label}.`);
    if (source.indexOf(search, first + search.length) !== -1) {
        throw new Error(`Anchor is ambiguous in ${label}; refusing to modify it.`);
    }
    return source.slice(0, first) + replacement + source.slice(first + search.length);
}

const original = Object.fromEntries(Object.entries(paths).map(([key, file]) => [key, fs.readFileSync(file, "utf8")]));
if (Object.values(original).every(text => text.includes(marker))) {
    const signatures = {
        config: "arbitrationHourOverride?: number;",
        world: "const configuredArbitrationTime = config.arbitrationHourOverride;",
        html: 'id="arbitration4Schedule"',
        script: "function arbitration4SaveValue(value)"
    };
    for (const [key, signature] of Object.entries(signatures)) {
        if (!original[key].includes(signature)) throw new Error(`Installed marker exists but ${key} is incomplete.`);
    }
    console.log("SpaceNinjaServer selector is already installed and structurally valid.");
    process.exit(0);
}
if (Object.values(original).some(text => text.includes(marker))) {
    throw new Error("A partial Arbitration4 server installation was detected; run the normal server updater before retrying.");
}

const htmlAnchor = '                        <div class="card d-none admin-show config-form">\n                            <h5 class="card-header" data-loc="worldState"></h5>';
let base = { ...original };
if (Object.values(base).some(text => text.includes(legacyMarker))) {
    if (!Object.values(base).every(text => text.includes(legacyMarker))) {
        throw new Error("A partial Arbitration4 V1 server installation was detected; refusing an unsafe upgrade.");
    }

    base.config = replaceExactlyOnce(
        base.config,
        `    arbitrationHourOverride?: number; // ${legacyMarker}\n`,
        "",
        "legacy configService.ts"
    );
    const legacyWorld =
        `    // ${legacyMarker}: the client derives the active Arbitration from WorldState.Time.\n` +
        `    const configuredArbitrationTime = config.arbitrationHourOverride;\n` +
        `    const timeSecs =\n` +
        `        typeof configuredArbitrationTime == "number" &&\n` +
        `        Number.isSafeInteger(configuredArbitrationTime) &&\n` +
        `        configuredArbitrationTime > 0\n` +
        `            ? configuredArbitrationTime\n` +
        `            : getIdealTimeSatsifyingConstraints(constraints);`;
    base.world = replaceExactlyOnce(
        base.world,
        legacyWorld,
        "    const timeSecs = getIdealTimeSatsifyingConstraints(constraints);",
        "legacy worldStateService.ts"
    );

    const legacyHtmlStart = base.html.indexOf(`                        <!-- ${legacyMarker} -->`);
    const legacyHtmlEnd = base.html.indexOf(htmlAnchor, legacyHtmlStart);
    if (legacyHtmlStart === -1 || legacyHtmlEnd === -1) {
        throw new Error("The Arbitration4 V1 HTML block could not be identified safely.");
    }
    base.html = base.html.slice(0, legacyHtmlStart) + base.html.slice(legacyHtmlEnd);

    const legacyScriptStart = base.script.indexOf(`\n// ${legacyMarker}\n`);
    if (legacyScriptStart === -1 || base.script.slice(legacyScriptStart).match(new RegExp(legacyMarker, "g"))?.length !== 1) {
        throw new Error("The Arbitration4 V1 script block could not be identified safely.");
    }
    base.script = base.script.slice(0, legacyScriptStart).trimEnd() + "\n";
}

const updated = { ...base };
updated.config = replaceExactlyOnce(
    updated.config,
    "    skipTutorial?: boolean;",
    `    skipTutorial?: boolean;\n    arbitrationHourOverride?: number; // ${marker}`,
    "configService.ts"
);

updated.world = replaceExactlyOnce(
    updated.world,
    "    const timeSecs = getIdealTimeSatsifyingConstraints(constraints);",
    `    // ${marker}: the client derives the active Arbitration from WorldState.Time.\n` +
        `    const configuredArbitrationTime = config.arbitrationHourOverride;\n` +
        `    const timeSecs =\n` +
        `        typeof configuredArbitrationTime == "number" &&\n` +
        `        Number.isSafeInteger(configuredArbitrationTime) &&\n` +
        `        configuredArbitrationTime > 0\n` +
        `            ? configuredArbitrationTime\n` +
        `            : getIdealTimeSatsifyingConstraints(constraints);`,
    "worldStateService.ts"
);

const htmlBlock = `                        <!-- ${marker} -->
                        <div class="card d-none admin-show mb-3">
                            <h5 class="card-header" id="arbitration4Title">Arbitration selector</h5>
                            <div class="card-body">
                                <p class="small text-body-secondary" id="arbitration4Description"></p>
                                <form class="form-group" onsubmit="arbitration4Save(); return false;">
                                    <label class="form-label" id="arbitration4ScheduleLabel" for="arbitration4Schedule">Arbitration</label>
                                    <select class="form-control" id="arbitration4Schedule"><option value="">Loading Arbitrations...</option></select>
                                    <input id="arbitrationHourOverride" type="hidden" value="0" />
                                    <div class="mt-2">
                                        <button class="btn btn-primary" id="arbitration4Apply" type="submit">Apply</button>
                                        <button class="btn btn-secondary" id="arbitration4Live" type="button" onclick="arbitration4Disable()">Live rotation</button>
                                    </div>
                                </form>
                                <div id="arbitration4Status" class="small mt-2"></div>
                            </div>
                        </div>
`;
updated.html = replaceExactlyOnce(updated.html, htmlAnchor, htmlBlock + htmlAnchor, "index.html");

const scriptBlock = `
// ${marker}
const arbitration4Ui = {
    en: {
        title: "Arbitration selector",
        description: "Choose one complete Arbitration. Mission, faction and node are applied together.",
        schedule: "Arbitration",
        loading: "Loading Arbitrations...",
        select: "Select an Arbitration",
        apply: "Apply",
        live: "Live rotation",
        saved: "Saved. Re-enter the mission to refresh the Arbitration.",
        restored: "Live Arbitration rotation restored.",
        saveFailed: "Save failed: ",
        chooseFirst: "Select an Arbitration first.",
        loadFailed: "Unable to load the browse.wf Arbitration data."
    },
    zh: {
        title: "仲裁选择器",
        description: "选择一个完整的仲裁任务；任务模式、阵营和节点会一起应用。",
        schedule: "仲裁任务",
        loading: "正在加载仲裁列表...",
        select: "选择一个仲裁任务",
        apply: "应用",
        live: "恢复实时轮换",
        saved: "已保存。重新进入任务以刷新仲裁。",
        restored: "已恢复实时仲裁轮换。",
        saveFailed: "保存失败：",
        chooseFirst: "请先选择一个仲裁任务。",
        loadFailed: "无法加载 browse.wf 仲裁数据。"
    }
};
const arbitration4State = { schedule: null, regions: null, dictionaries: new Map() };

function arbitration4Language() {
    return window.lang == "zh" ? "zh" : "en";
}

function arbitration4Text(key) {
    return arbitration4Ui[arbitration4Language()][key];
}

function arbitration4SetUiLanguage() {
    const values = {
        arbitration4Title: "title",
        arbitration4Description: "description",
        arbitration4ScheduleLabel: "schedule",
        arbitration4Apply: "apply",
        arbitration4Live: "live"
    };
    for (const [id, key] of Object.entries(values)) {
        const element = document.getElementById(id);
        if (element) element.textContent = arbitration4Text(key);
    }
}

function arbitration4TitleCase(value) {
    return String(value ?? "")
        .toLowerCase()
        .replace(/(^|[\\s_-])([a-z])/g, (_match, prefix, letter) => prefix + letter.toUpperCase());
}

function arbitration4FactionName(value) {
    return arbitration4TitleCase(String(value ?? "Unknown").replace(/^FC_/, "").replaceAll("_", " "));
}

function arbitration4Lookup(dictionary, key, fallback) {
    const value = dictionary?.[key];
    return typeof value == "string" && value.trim() ? value.trim() : fallback;
}

async function arbitration4FetchJson(url, label) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(label + " HTTP " + response.status);
    return response.json();
}

async function arbitration4Dictionary(language) {
    if (!arbitration4State.dictionaries.has(language)) {
        const promise = arbitration4FetchJson(
            "https://browse.wf/warframe-public-export-plus/dict." + language + ".json",
            "dictionary"
        );
        arbitration4State.dictionaries.set(language, promise);
    }
    return arbitration4State.dictionaries.get(language);
}

async function arbitration4LoadData() {
    if (arbitration4State.schedule && arbitration4State.regions) return;
    const [scheduleText, regions] = await Promise.all([
        fetch("https://browse.wf/arbys.txt").then(response => {
            if (!response.ok) throw new Error("schedule HTTP " + response.status);
            return response.text();
        }),
        arbitration4FetchJson(
            "https://browse.wf/warframe-public-export-plus/ExportRegions.json",
            "regions"
        )
    ]);
    const now = Math.trunc(Date.now() / 3600000) * 3600;
    arbitration4State.schedule = scheduleText.trim().split(/\\r?\\n/)
        .map(line => line.split(","))
        .filter(parts => parts.length == 2)
        .map(parts => ({ time: Number(parts[0]), nodeId: parts[1] }))
        .filter(entry => Number.isSafeInteger(entry.time) && entry.time >= now)
        .slice(0, 24 * 180);
    arbitration4State.regions = regions;
}

async function arbitration4RenderSchedule() {
    const select = document.getElementById("arbitration4Schedule");
    if (!select) return;
    arbitration4SetUiLanguage();
    select.replaceChildren(new Option(arbitration4Text("loading"), ""));
    try {
        await arbitration4LoadData();
        const language = arbitration4Language();
        const [localizedDictionary, englishDictionary] = await Promise.all([
            arbitration4Dictionary(language),
            arbitration4Dictionary("en")
        ]);
        const options = [];
        const seen = new Set();
        for (const entry of arbitration4State.schedule) {
            const node = arbitration4State.regions[entry.nodeId];
            if (!node) continue;
            const missionFallback = arbitration4TitleCase(String(node.missionType ?? "Unknown").replace(/^MT_/, ""));
            const localizedMission = arbitration4Lookup(localizedDictionary, node.missionName, missionFallback);
            const mission = language == "en" ? arbitration4TitleCase(localizedMission) : localizedMission;
            const nodeName = arbitration4Lookup(englishDictionary, node.name, entry.nodeId);
            const planet = arbitration4Lookup(localizedDictionary, node.systemName, "Unknown");
            const faction = arbitration4FactionName(node.faction);
            const label = mission + " - " + faction + " @ " + nodeName + ", " + planet;
            const identity = [mission, faction, nodeName, planet].join("\\u0000");
            if (seen.has(identity)) continue;
            seen.add(identity);
            options.push({ label, time: entry.time });
        }
        options.sort((a, b) => a.label.localeCompare(b.label, language));
        select.replaceChildren(new Option(arbitration4Text("select"), ""));
        for (const option of options) select.add(new Option(option.label, String(option.time)));
        select.onchange = () => {
            if (select.value) document.getElementById("arbitrationHourOverride").value = select.value;
        };
    } catch (error) {
        select.replaceChildren(new Option(arbitration4Text("loadFailed"), ""));
        document.getElementById("arbitration4Status").textContent = String(error);
    }
}

async function arbitration4LoadSchedule() {
    const select = document.getElementById("arbitration4Schedule");
    if (!select || select.dataset.loaded) return;
    select.dataset.loaded = "1";
    await arbitration4RenderSchedule();
}

function arbitration4SaveValue(value) {
    const status = document.getElementById("arbitration4Status");
    $.post({
        url: "/custom/setConfig?" + window.authz,
        contentType: "application/json",
        data: JSON.stringify({ arbitrationHourOverride: value })
    }).done(function () {
        document.getElementById("arbitrationHourOverride").value = value;
        status.textContent = value > 0 ? arbitration4Text("saved") : arbitration4Text("restored");
    }).fail(function (_xhr, _status, error) {
        status.textContent = arbitration4Text("saveFailed") + error;
    });
}

function arbitration4Save() {
    const select = document.getElementById("arbitration4Schedule");
    const value = Number(select.value);
    if (!Number.isSafeInteger(value) || value <= 0) {
        document.getElementById("arbitration4Status").textContent = arbitration4Text("chooseFirst");
        return;
    }
    arbitration4SaveValue(value);
}

function arbitration4Disable() {
    arbitration4SaveValue(0);
}

const arbitration4OriginalSetLanguage = setLanguage;
setLanguage = function (language) {
    arbitration4OriginalSetLanguage(language);
    arbitration4RenderSchedule();
};

document.addEventListener("DOMContentLoaded", arbitration4LoadSchedule);
arbitration4LoadSchedule();
`;
updated.script += scriptBlock;

// Perform every compatibility check before the first write. Writes are limited to these four known files.
for (const key of Object.keys(paths)) {
    if (updated[key] === original[key]) throw new Error(`No change was produced for ${key}.`);
}
if (checkOnly) {
    console.log("SpaceNinjaServer selector compatibility check passed.");
} else {
    for (const key of Object.keys(paths)) fs.writeFileSync(paths[key], updated[key], "utf8");
    console.log("SpaceNinjaServer Arbitration selector installed.");
}
