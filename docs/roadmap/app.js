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

fetch("roadmap.json")
  .then((response) => {
    if (!response.ok) {
      throw new Error(`roadmap.json returned ${response.status}`);
    }
    return response.json();
  })
  .then((data) => {
    state.data = data;
    render();
    bindControls();
  })
  .catch((error) => {
    els.purpose.textContent = `Unable to load roadmap data: ${error.message}`;
  });

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
  els.generated.textContent = `Data generated ${formatDate(data.generatedAt)}`;
  renderMetrics();
  renderFilters();
  renderComponents();
  renderPhases();
  renderPolicies();
  renderBacklog();
}

function renderMetrics() {
  const summary = state.data.statusSummary;
  const metrics = [
    ["Tracked areas", summary.trackedComponentAreas],
    ["Rust-default RC", summary.rustDefaultRcAreas],
    ["Opt-in only", summary.rustOptInOnlyAreas],
    ["Retired C areas", summary.retiredAreas]
  ];

  els.metrics.replaceChildren(
    ...metrics.map(([label, value]) => {
      const node = el("div", "metric");
      node.append(el("strong", "", String(value)), el("span", "", label));
      return node;
    })
  );
}

function renderFilters() {
  const components = state.data.components;
  fillOptions(els.stateFilter, ["all", ...unique(components.map((item) => item.currentState))]);
  fillOptions(els.areaFilter, ["all", ...unique(components.map((item) => item.area))]);
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
    el("span", "tag", component.cDefault ? "C rollback" : "No C default"),
    el("span", "tag", component.rustDefault ? "Rust default RC" : "Rust opt-in"),
    el("span", `tag risk-${slug(component.risk)}`, `Risk: ${component.risk}`)
  );

  card.append(top, tags);
  card.append(el("p", "", component.notes));
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
      wrap([el("h3", "", phase.name), el("p", "", phase.objective)])
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
    td.colSpan = 5;
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
      cell(item.files.join("\n"), "file-list")
    );
    tr.title = item.notes;
    return tr;
  }));
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
    component.evidence.join(" ")
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
    item.files.join(" ")
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
  return value
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function slug(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-");
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
