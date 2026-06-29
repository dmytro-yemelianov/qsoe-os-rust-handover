const REPO_OWNER = "dmytro-yemelianov";
const REPO_NAME = "qsoe-os-rust-handover";
const ROADMAP_LABEL = "roadmap";
const ISSUES_API_URL = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues?state=all&labels=${ROADMAP_LABEL}&per_page=100`;
const ROADMAP_ISSUES_URL = `https://github.com/${REPO_OWNER}/${REPO_NAME}/issues?q=label%3A${ROADMAP_LABEL}`;
const ROADMAP_META_RE = /<!--\s*qsoe-roadmap:v1\s*([\s\S]*?)\s*-->/;

const PURPOSE = {
  summary: "Make the QSOE Rust migration measurable, reversible, and reviewable instead of a rewrite for its own sake.",
  whyRust: [
    "Reduce concrete C failure modes in parsers, state machines, resource servers, and image tooling.",
    "Use Rust type, ownership, and Result-based error handling where they improve maintenance and review quality.",
    "Keep high-risk boot, loader, spawn, capability, and kernel-adjacent code in C until boundaries are proven."
  ],
  operatingRule: "Every Rust candidate needs a selector, C rollback path, host tests, runtime or boot evidence, and documentation before it can become a default. C is not removed just because a Rust version exists."
};

const POLICY_GATES = [
  {
    id: "selector",
    name: "Selector",
    description: "Rust implementation must be selectable without removing the C implementation."
  },
  {
    id: "rollback",
    name: "C rollback",
    description: "A one-command C rollback path must exist and be tested."
  },
  {
    id: "host-tests",
    name: "Host tests",
    description: "Pure logic, parser, and model code should have host tests before guest wiring."
  },
  {
    id: "runtime-evidence",
    name: "Runtime evidence",
    description: "Image-level or service-level smoke tests must prove the behavior in QSOE."
  },
  {
    id: "retirement",
    name: "Retirement review",
    description: "Removing C requires the retirement checklist and a separate removal PR."
  }
];

const PHASE_SCORE = {
  complete: 100,
  "complete-for-current-scope": 85,
  "rust-default-rc": 75,
  "in-progress": 50,
  started: 30,
  deferred: 0
};

const state = {
  data: null,
  filters: {
    search: "",
    state: "all",
    area: "all",
    risk: "all"
  }
};

const els = {
  purpose: document.querySelector("#purpose"),
  metrics: document.querySelector("#metrics"),
  whySummary: document.querySelector("#why-summary"),
  whyRule: document.querySelector("#why-rule"),
  whyPoints: document.querySelector("#why-points"),
  progressNote: document.querySelector("#progress-note"),
  progressGauges: document.querySelector("#progress-gauges"),
  stateChart: document.querySelector("#state-chart"),
  riskChart: document.querySelector("#risk-chart"),
  phaseChart: document.querySelector("#phase-chart"),
  backlogChart: document.querySelector("#backlog-chart"),
  components: document.querySelector("#components"),
  componentCount: document.querySelector("#component-count"),
  phases: document.querySelector("#phases"),
  policies: document.querySelector("#policies"),
  backlog: document.querySelector("#backlog"),
  backlogCount: document.querySelector("#backlog-count"),
  generated: document.querySelector("#generated"),
  search: document.querySelector("#search"),
  stateFilter: document.querySelector("#state-filter"),
  areaFilter: document.querySelector("#area-filter"),
  riskFilter: document.querySelector("#risk-filter")
};

loadRoadmap();

function loadRoadmap() {
  fetchRoadmapIssues(ISSUES_API_URL)
    .then((issues) => {
      state.data = normalizeIssueRoadmap(issues);
      render();
      bindControls();
    })
    .catch((error) => {
      els.purpose.textContent = `Unable to load roadmap issues: ${error.message}`;
    });
}

function fetchRoadmapIssues(url, collected = []) {
  return fetch(url, {
    headers: {
      Accept: "application/vnd.github+json"
    }
  })
    .then((response) => {
      if (!response.ok) {
        throw new Error(`GitHub Issues API returned ${response.status}`);
      }
      return response.json().then((issues) => ({
        issues,
        nextUrl: nextLink(response.headers.get("Link"))
      }));
    })
    .then(({ issues, nextUrl }) => {
      const nextCollected = [...collected, ...issues];
      if (nextUrl) {
        return fetchRoadmapIssues(nextUrl, nextCollected);
      }
      return nextCollected;
    });
}

function nextLink(header) {
  if (!header) {
    return "";
  }
  const part = header.split(",").find((item) => item.includes('rel="next"'));
  const match = part && /<([^>]+)>/.exec(part);
  return match ? match[1] : "";
}

function normalizeIssueRoadmap(issues) {
  const items = issues
    .filter((issue) => !issue.pull_request)
    .map(parseRoadmapIssue)
    .filter(Boolean);

  if (items.length === 0) {
    throw new Error("no issues with qsoe-roadmap metadata were found");
  }

  const components = items
    .filter((item) => item.kind === "component")
    .map(normalizeComponent)
    .sort(byOrderThenName);
  const roadmapPhases = items
    .filter((item) => item.kind === "phase")
    .map(normalizePhase)
    .sort(byOrderThenName);
  const candidateBacklog = items
    .filter((item) => item.kind === "backlog")
    .map(normalizeBacklog)
    .sort(byOrderThenName);
  const generatedAt = latestIssueUpdate(items);

  return {
    schemaVersion: 1,
    generatedAt,
    title: "QSOE C-to-Rust Migration Roadmap",
    purpose: PURPOSE,
    statusSummary: {
      trackedComponents: components.length,
      rustDefaultRcComponents: components.filter((component) => component.rustDefault).length,
      rustOptInOnlyImplementations: components.filter((component) => component.currentState === "mixed").length,
      retiredCComponents: components.filter((component) => component.retired).length
    },
    sourceIssueCount: items.length,
    sourceIssuesUrl: ROADMAP_ISSUES_URL,
    components,
    roadmapPhases,
    candidateBacklog,
    policyGates: POLICY_GATES
  };
}

function parseRoadmapIssue(issue) {
  const match = ROADMAP_META_RE.exec(issue.body || "");
  if (!match) {
    return null;
  }

  try {
    return {
      ...JSON.parse(match[1]),
      issue: {
        number: issue.number,
        title: issue.title,
        state: issue.state.toLowerCase(),
        url: issue.html_url,
        updatedAt: issue.updated_at
      }
    };
  } catch (error) {
    console.warn(`Skipping malformed roadmap issue #${issue.number}`, error);
    return null;
  }
}

function normalizeComponent(item) {
  return {
    ...item,
    name: item.name,
    area: item.area || "unknown",
    currentState: item.currentState || item.status || "unknown",
    risk: item.risk || "unknown",
    cDefault: Boolean(item.cDefault),
    rustOptIn: Boolean(item.rustOptIn),
    rustDefault: Boolean(item.rustDefault),
    retired: Boolean(item.retired),
    rustArtifacts: item.rustArtifacts || [],
    cRollback: item.cRollback || [],
    selectors: item.selectors || [],
    evidence: item.evidence || [],
    notes: item.notes || "",
    nextGate: item.nextGate || ""
  };
}

function normalizePhase(item) {
  return {
    ...item,
    name: item.name,
    status: item.status || "unknown",
    objective: item.summary || item.objective || ""
  };
}

function normalizeBacklog(item) {
  return {
    ...item,
    name: item.name,
    area: item.area || "unknown",
    risk: item.risk || "unknown",
    posture: item.posture || item.status || "unknown",
    files: item.files || [],
    notes: item.notes || ""
  };
}

function bindControls() {
  els.search.addEventListener("input", (event) => {
    state.filters.search = event.target.value.trim().toLowerCase();
    renderComponents();
    renderBacklog();
  });

  for (const [key, element] of [
    ["state", els.stateFilter],
    ["area", els.areaFilter],
    ["risk", els.riskFilter]
  ]) {
    element.addEventListener("change", (event) => {
      state.filters[key] = event.target.value;
      renderComponents();
      renderBacklog();
    });
  }
}

function render() {
  const { data } = state;
  document.title = data.title;
  els.purpose.textContent = data.purpose.summary;
  els.generated.textContent =
    `Issue tracker refreshed ${formatDate(data.generatedAt)} from ${data.sourceIssueCount} roadmap issues`;
  renderMetrics();
  renderWhy();
  renderProgressVisuals();
  renderFilters();
  renderComponents();
  renderPhases();
  renderPolicies();
  renderBacklog();
}

function renderMetrics() {
  const summary = state.data.statusSummary;
  const metrics = [
    ["Tracked components", summary.trackedComponents],
    ["Rust-default RC components", summary.rustDefaultRcComponents],
    ["Opt-in implementations", summary.rustOptInOnlyImplementations],
    ["Retired C components", summary.retiredCComponents]
  ];

  els.metrics.replaceChildren(
    ...metrics.map(([label, value]) => {
      const node = el("div", "metric");
      node.append(el("strong", "", String(value)), el("span", "", label));
      return node;
    })
  );
}

function renderWhy() {
  const { purpose } = state.data;
  els.whySummary.textContent = purpose.summary;
  els.whyRule.textContent = purpose.operatingRule;
  els.whyPoints.replaceChildren(...purpose.whyRust.map((point, index) => {
    const card = el("article", "why-card");
    card.append(el("span", "why-index", String(index + 1).padStart(2, "0")), el("p", "", point));
    return card;
  }));
}

function renderProgressVisuals() {
  const { components, roadmapPhases, candidateBacklog } = state.data;
  const componentReadiness = Math.round(avg(components.map(componentScore)));
  const phaseReadiness = Math.round(avg(roadmapPhases.map((phase) => PHASE_SCORE[phase.status] ?? 0)));
  const rustDefaultCount = components.filter((component) => component.rustDefault).length;
  const rollbackCount = components.filter((component) => component.cRollback.length > 0).length;
  const retiredCount = components.filter((component) => component.retired).length;
  const overallReadiness = Math.round(avg([componentReadiness, phaseReadiness]));

  els.progressNote.textContent =
    "Computed from roadmap issues: tracked components, rollback coverage, phase status, and remaining backlog posture.";

  els.progressGauges.replaceChildren(
    gauge("Overall readiness", overallReadiness, "Component posture + phase completion", "accent"),
    gauge("Rust-default RC coverage", pct(rustDefaultCount, components.length), `${rustDefaultCount}/${components.length} tracked components`, "good"),
    gauge("Rollback coverage", pct(rollbackCount, components.length), `${rollbackCount}/${components.length} components keep C rollback`, "info"),
    gauge("C retirement progress", pct(retiredCount, components.length), `${retiredCount}/${components.length} C implementations retired`, "warn")
  );

  renderBarChart(els.stateChart, countBy(components, "currentState"));
  renderBarChart(els.riskChart, countBy([...components, ...candidateBacklog], "risk"));
  renderBarChart(els.phaseChart, countBy(roadmapPhases, "status"));
  renderBarChart(els.backlogChart, countBy(candidateBacklog, "posture"));
}

function renderFilters() {
  const components = state.data.components;
  fillOptions(els.stateFilter, ["all", ...unique(components.map((item) => item.currentState))]);
  fillOptions(els.areaFilter, ["all", ...unique([
    ...components.map((item) => item.area),
    ...state.data.candidateBacklog.map((item) => item.area)
  ])]);
  fillOptions(els.riskFilter, ["all", ...unique([
    ...components.map((item) => item.risk),
    ...state.data.candidateBacklog.map((item) => item.risk)
  ])]);
}

function renderComponents() {
  const rows = state.data.components.filter(matchesComponentFilters);
  els.componentCount.textContent = `${rows.length} shown of ${state.data.components.length}`;

  if (rows.length === 0) {
    els.components.replaceChildren(el("div", "empty", "No components match the current filters."));
    return;
  }

  els.components.replaceChildren(...rows.map(renderComponentCard));
}

function renderComponentCard(component) {
  const card = el("article", "component-card");
  const top = el("div", "card-top");
  const titleWrap = el("div");
  titleWrap.append(el("h3", "", component.name), el("p", "", component.area));
  top.append(titleWrap, el("span", `pill state ${component.currentState}`, readable(component.currentState)));

  const tags = el("div", "tag-row");
  tags.append(
    el("span", "tag", component.cDefault ? "C default" : "C not default"),
    el("span", "tag", component.rustDefault ? "Rust default RC" : "Rust opt-in"),
    el("span", `tag risk-${slug(component.risk)}`, `Risk: ${component.risk}`),
    issueLink(component.issue)
  );

  card.append(top, tags);
  card.append(el("p", "", component.notes));
  card.append(meter(componentScore(component), "Readiness"));
  card.append(el("h3", "", "Selectors"), list(component.selectors, "selector-list"));
  card.append(el("h3", "", "Evidence"), list(component.evidence, "evidence-list"));
  card.append(el("p", "next-gate", component.nextGate));
  return card;
}

function renderPhases() {
  els.phases.replaceChildren(...state.data.roadmapPhases.map((phase) => {
    const node = el("article", "phase");
    node.append(
      el("span", "phase-status", readable(phase.status)),
      wrap([
        withInlineLink(el("h3", "", phase.name), phase.issue),
        el("p", "", phase.objective),
        meter(PHASE_SCORE[phase.status] ?? 0, "Phase completion")
      ])
    );
    return node;
  }));
}

function renderPolicies() {
  els.policies.replaceChildren(...state.data.policyGates.map((policy) => {
    const node = el("article", "policy");
    node.append(
      el("span", "phase-status", policy.name),
      wrap([el("p", "", policy.description)])
    );
    return node;
  }));
}

function renderBacklog() {
  const rows = state.data.candidateBacklog.filter(matchesBacklogFilters);
  els.backlogCount.textContent = `${rows.length} shown of ${state.data.candidateBacklog.length}`;

  if (rows.length === 0) {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.colSpan = 6;
    td.className = "empty";
    td.textContent = "No candidates match the current filters.";
    tr.append(td);
    els.backlog.replaceChildren(tr);
    return;
  }

  els.backlog.replaceChildren(...rows.map((item) => {
    const tr = document.createElement("tr");
    tr.append(
      cell(item.name),
      cell(item.area),
      cell(item.risk, `risk-${slug(item.risk)}`),
      cell(readable(item.posture)),
      cell(item.files.join("\n"), "file-list"),
      issueCell(item.issue)
    );
    tr.title = item.notes;
    return tr;
  }));
}

function gauge(label, value, detail, tone) {
  const bounded = clamp(value, 0, 100);
  const card = el("article", `gauge-card tone-${tone}`);
  const dial = el("div", "gauge-dial");
  dial.style.setProperty("--value", `${bounded}%`);
  dial.setAttribute("aria-label", `${label}: ${bounded}%`);
  dial.append(el("span", "gauge-value", `${bounded}%`));
  card.append(dial, el("h3", "", label), el("p", "", detail));
  return card;
}

function renderBarChart(container, rows) {
  const total = rows.reduce((sum, row) => sum + row.count, 0);
  container.replaceChildren(...rows.map((row) => {
    const node = el("div", "bar-row");
    const label = el("div", "bar-label");
    label.append(el("span", "", readable(row.label)), el("strong", "", String(row.count)));

    const track = el("div", "bar-track");
    const fill = el("div", `bar-fill risk-${slug(row.label)}`);
    fill.style.setProperty("--bar-value", `${pct(row.count, total)}%`);
    track.append(fill);

    node.append(label, track);
    return node;
  }));
}

function meter(value, label) {
  const bounded = clamp(value, 0, 100);
  const node = el("div", "meter");
  const copy = el("div", "meter-copy");
  copy.append(el("span", "", label), el("strong", "", `${bounded}%`));
  const track = el("div", "meter-track");
  const fill = el("div", "meter-fill");
  fill.style.setProperty("--meter-value", `${bounded}%`);
  track.append(fill);
  node.append(copy, track);
  return node;
}

function matchesComponentFilters(component) {
  return matchesCommonFilters(component) && matchesSearch(component, [
    component.name,
    component.area,
    component.currentState,
    component.risk,
    component.notes,
    component.nextGate,
    component.selectors.join(" "),
    component.evidence.join(" "),
    `#${component.issue.number}`,
    component.issue.title
  ]);
}

function matchesBacklogFilters(item) {
  const filterArea = state.filters.area === "all" || item.area === state.filters.area;
  const filterRisk = state.filters.risk === "all" || item.risk === state.filters.risk;
  return filterArea && filterRisk && matchesSearch(item, [
    item.name,
    item.area,
    item.risk,
    item.posture,
    item.notes,
    item.files.join(" "),
    `#${item.issue.number}`,
    item.issue.title
  ]);
}

function matchesCommonFilters(item) {
  const filterState = state.filters.state === "all" || item.currentState === state.filters.state;
  const filterArea = state.filters.area === "all" || item.area === state.filters.area;
  const filterRisk = state.filters.risk === "all" || item.risk === state.filters.risk;
  return filterState && filterArea && filterRisk;
}

function matchesSearch(_item, values) {
  if (!state.filters.search) {
    return true;
  }
  return values.join(" ").toLowerCase().includes(state.filters.search);
}

function fillOptions(select, values) {
  select.replaceChildren(...values.map((value) => {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = value === "all" ? "All" : readable(value);
    return option;
  }));
}

function list(items, className) {
  const node = el("ul", className);
  node.append(...items.map((item) => el("li", "", item)));
  return node;
}

function cell(text, className = "") {
  const td = document.createElement("td");
  td.className = className;
  td.textContent = text;
  return td;
}

function issueCell(issue) {
  const td = document.createElement("td");
  td.append(issueLink(issue));
  return td;
}

function issueLink(issue) {
  const link = el("a", "issue-link", `#${issue.number}`);
  link.href = issue.url;
  link.target = "_blank";
  link.rel = "noreferrer";
  link.title = issue.title;
  return link;
}

function withInlineLink(node, issue) {
  const wrapNode = el("div", "inline-heading");
  wrapNode.append(node, issueLink(issue));
  return wrapNode;
}

function countBy(items, key) {
  const counts = new Map();
  for (const item of items) {
    const value = item[key] ?? "unknown";
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

function componentScore(component) {
  if (component.retired) {
    return 100;
  }
  if (component.rustDefault && component.cRollback.length > 0) {
    return 75;
  }
  if (component.rustDefault) {
    return 65;
  }
  if (component.rustOptIn) {
    return 45;
  }
  if (component.cDefault) {
    return 20;
  }
  return 0;
}

function latestIssueUpdate(items) {
  return items
    .map((item) => item.issue.updatedAt)
    .sort((a, b) => new Date(b) - new Date(a))[0];
}

function byOrderThenName(a, b) {
  return (a.order ?? 0) - (b.order ?? 0) || a.name.localeCompare(b.name);
}

function avg(values) {
  if (values.length === 0) {
    return 0;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function pct(value, total) {
  if (total === 0) {
    return 0;
  }
  return Math.round((value / total) * 100);
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function wrap(children) {
  const node = el("div");
  node.append(...children);
  return node;
}

function el(tag, className = "", text = "") {
  const node = document.createElement(tag);
  if (className) {
    node.className = className;
  }
  if (text) {
    node.textContent = text;
  }
  return node;
}

function unique(values) {
  return [...new Set(values)].sort((a, b) => a.localeCompare(b));
}

function readable(value) {
  return String(value)
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function slug(value) {
  return String(value).toLowerCase().replace(/[^a-z0-9]+/g, "-");
}

function formatDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short"
  });
}
