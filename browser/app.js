"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const demos = JSON.parse($("demo-source").textContent);
  const engine = JSON.parse($("engine-source").textContent);
  $("license-text").textContent = JSON.parse($("license-source").textContent);
  const PAGE = 12;
  const state = {
    value: null,
    label: "",
    tab: "pending",
    page: 0,
    edits: new Map(),
    uniqueEdits: new Map(),
    busy: false,
    id: 0,
    operation: 0,
    demo: null,
    worker: null,
  };
  const names = {
    ColumnDeleteEdit: "字段删除冲突",
    RowDeleteEdit: "记录删除冲突",
    ConcurrentInsert: "同主键新增冲突",
    CellEdit: "单元格修改冲突",
    MissingCell: "交叉单元格缺失",
  };
  const labels = {
    keep: "保留整个对象",
    drop: "删除整个对象",
    base: "采用共同祖先",
    ours: "采用当前版本",
    theirs: "采用另一版本",
    value: "填写明确值",
  };
  const workerCode =
    engine +
    "\nself.onmessage = ({data}) => { try { const methods = {begin:10,open:1,update:2,export:2,unique:2,repair:2}; if (!Object.hasOwn(methods,data.method) || !Array.isArray(data.args) || data.args.length !== methods[data.method] || data.args.some(x => typeof x !== 'string')) throw new Error('Invalid worker request'); const result = globalThis['mt_'+data.method](...data.args); self.postMessage({id:data.id,result}); } catch(e) { self.postMessage({id:data.id,error:String(e)}); } };";
  const url = URL.createObjectURL(
    new Blob([workerCode], { type: "text/javascript" }),
  );
  let waiter = null;
  function spawn() {
    const worker = new Worker(url);
    state.worker = worker;
    worker.onmessage = ({ data }) => {
      if (worker !== state.worker) return;
      if (!waiter || data.id !== waiter.id) return;
      const current = waiter;
      waiter = null;
      if (data.error) current.reject(new Error(data.error));
      else {
        try {
          const result = JSON.parse(data.result);
          if (!result.ok) throw new Error(result.message);
          current.resolve(result.value);
        } catch (e) {
          current.reject(e);
        }
      }
    };
    worker.onerror = (event) => {
      if (worker === state.worker && waiter) {
        waiter.reject(
          new Error(
            event.message || "浏览器处理失败，可保存当前审阅包后重试。",
          ),
        );
        waiter = null;
      }
    };
  }
  function call(method, args) {
    return new Promise((resolve, reject) => {
      const id = ++state.id;
      waiter = { id, resolve, reject };
      state.worker.postMessage({ id, method, args });
    });
  }
  function error(e) {
    $("error").textContent = e.message || String(e);
    $("error").hidden = false;
  }
  function busy(on) {
    state.busy = on;
    document.body.classList.toggle("busy", on);
    $("cancel").hidden = !on;
    for (const id of [
      "begin",
      "open-review",
      "replay-inputs",
      "apply",
      "demo-simple",
      "demo-evolution",
      "demo-unique",
      "tab-pending",
      "tab-resolved",
      "previous",
      "next",
    ])
      $(id).disabled = on;
    document
      .querySelectorAll("input,select,textarea")
      .forEach((control) => (control.disabled = on));
    if (!on && state.value) render();
    $("download-csv").disabled = on || !state.value?.report.complete;
    $("download-tsv").disabled = on || !state.value?.report.complete;
  }
  async function perform(action) {
    if (state.busy) return;
    const operation = ++state.operation;
    $("error").hidden = true;
    busy(true);
    try {
      await action();
    } catch (e) {
      if (operation === state.operation) error(e);
    } finally {
      if (operation === state.operation) busy(false);
    }
  }
  async function read(file, role) {
    if (!file) throw new Error("请选择" + role + "文件。");
    if (file.size > 8000000)
      throw new Error(role + "文件超过 8,000,000 字节，请使用 CLI 处理。");
    let bytes;
    try {
      bytes = await file.arrayBuffer();
    } catch (e) {
      throw new Error(
        role + "无法读取，请重新选择可读的本地文件：" + e.message,
      );
    }
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch (e) {
      throw new Error(role + "不是有效的 UTF-8 文件，未替换或丢弃任何字符。");
    }
  }
  function accept(value, label) {
    state.value = value;
    state.label = label;
    state.page = 0;
    state.edits.clear();
    state.uniqueEdits.clear();
    if (value.report.conflicts.length || value.report.unique_conflicts?.length)
      state.tab = "pending";
    $("workspace").hidden = false;
    $("exports").hidden = false;
    render();
  }
  function targetText(target) {
    if (target.row && target.column !== undefined)
      return "记录 " + JSON.stringify(target.row) + " · " + target.column;
    if (target.row) return "记录 " + JSON.stringify(target.row);
    return "字段 " + target.column;
  }
  function element(tag, text, className) {
    const item = document.createElement(tag);
    if (text !== undefined) item.textContent = text;
    if (className) item.className = className;
    return item;
  }
  function choiceName(choice) {
    return choice && typeof choice === "object" ? "value" : choice;
  }
  function allowed(conflict) {
    if (["ColumnDeleteEdit", "RowDeleteEdit"].includes(conflict.kind))
      return ["keep", "drop"];
    if (conflict.kind === "ConcurrentInsert") return ["ours", "theirs", "drop"];
    return ["base", "ours", "theirs"]
      .filter((side) => conflict[side].length)
      .concat("value");
  }
  function sources(conflict) {
    const box = element("div", undefined, "sources");
    for (const [side, label] of [
      ["base", "共同祖先"],
      ["ours", "当前版本"],
      ["theirs", "另一版本"],
    ]) {
      const column = element("div", undefined, "source");
      column.append(
        element("h4", label + " · " + conflict[side].length + " 项"),
      );
      const list = element("ul");
      if (!conflict[side].length)
        list.append(element("li", "此来源无可用单元格值", "hint"));
      for (const value of conflict[side].slice(0, 50)) {
        const row = element("li");
        row.append(
          element(
            "span",
            JSON.stringify(value.row) + " / " + value.column,
            "coordinate",
          ),
        );
        row.append(
          element(
            "span",
            value.value === "" ? "〈空字符串〉" : value.value,
            value.value === "" ? "empty-value" : "",
          ),
        );
        list.append(row);
      }
      column.append(list);
      if (conflict[side].length > 50)
        column.append(
          element(
            "span",
            "仅预览前 50 项；完整内容保存在证据与审阅包中。",
            "hint",
          ),
        );
      box.append(column);
    }
    return box;
  }
  function card(conflict, recorded) {
    const key = JSON.stringify(conflict.target);
    const draft = state.edits.get(key) || {
      target: conflict.target,
      choice: recorded?.choice ?? null,
      revoke: false,
    };
    const section = element("article", undefined, "conflict");
    const head = element("div", undefined, "conflict-head");
    head.append(
      element("div", targetText(conflict.target), "target"),
      element("span", names[conflict.kind] || conflict.kind, "kind"),
    );
    section.append(head, sources(conflict));
    const form = element("div", undefined, "decision");
    const label = element(
      "label",
      recorded ? "已记录的选择 / 修改" : "此项如何处理",
    );
    const select = element("select");
    select.setAttribute("aria-label", "处理：" + targetText(conflict.target));
    select.append(new Option(recorded ? "保留原决策" : "暂不决定", ""));
    for (const option of allowed(conflict))
      select.append(new Option(labels[option], option));
    const current = choiceName(draft.choice);
    select.value = draft.choice ? current : "";
    const customLabel = element(
      "label",
      "明确值（允许空字符串，保留空格与换行）",
    );
    const custom = element("textarea");
    custom.rows = 3;
    custom.setAttribute("aria-label", "明确值：" + targetText(conflict.target));
    custom.value = current === "value" ? draft.choice.value : "";
    customLabel.hidden = select.value !== "value";
    customLabel.append(custom);
    function save() {
      const choice =
        select.value === "value"
          ? { value: custom.value }
          : select.value || null;
      draft.choice = choice;
      if (
        !draft.revoke &&
        (!choice ||
          (recorded &&
            JSON.stringify(choice) === JSON.stringify(recorded.choice)))
      )
        state.edits.delete(key);
      else state.edits.set(key, draft);
      customLabel.hidden = select.value !== "value";
      updateApply();
    }
    select.addEventListener("change", save);
    custom.addEventListener("input", save);
    label.append(select);
    form.append(label, customLabel);
    section.append(form);
    if (recorded) {
      const revokeLabel = element("label", undefined, "revoke");
      const check = element("input");
      check.type = "checkbox";
      check.checked = draft.revoke;
      const sync = () => {
        draft.revoke = check.checked;
        select.disabled = check.checked;
        custom.disabled = check.checked;
        save();
      };
      check.setAttribute("aria-label", "撤销：" + targetText(conflict.target));
      check.addEventListener("change", sync);
      select.disabled = check.checked;
      custom.disabled = check.checked;
      revokeLabel.append(check, document.createTextNode("明确撤销此决策"));
      section.append(revokeLabel);
    }
    return section;
  }
  function updateApply() {
    const count = state.edits.size + state.uniqueEdits.size;
    $("apply").textContent =
      "应用所选决策" + (count ? "（" + count + " 项）" : "");
  }
  function uniqueCard(group) {
    const section = element("article", undefined, "conflict");
    section.append(
      element("h3", "唯一性冲突 · " + group.rule),
      element(
        "p",
        JSON.stringify(group.columns) + " = " + JSON.stringify(group.values),
      ),
    );
    section.append(sources(group));
    const details = element("details");
    details.append(
      element("summary", "当前合并值 · " + group.rows.length + " 条涉事记录"),
    );
    details.append(
      element(
        "pre",
        JSON.stringify(group.merged.slice(0, 50), null, 2),
        "unique-preview",
      ),
    );
    if (group.merged.length > 50)
      details.append(
        element("p", "仅预览前 50 项单元格；完整内容可下载。", "hint"),
      );
    section.append(details);
    return section;
  }
  function uniqueDraft(edit, active) {
    const token = JSON.stringify(edit.target);
    if (active) state.uniqueEdits.set(token, edit);
    else state.uniqueEdits.delete(token);
    updateApply();
  }
  function uniqueForms(groups, keys) {
    const rows = new Map();
    for (const group of groups)
      for (const row of group.rows) {
        const token = JSON.stringify(row);
        if (!rows.has(token) && rows.size >= 12) continue;
        if (!rows.has(token)) rows.set(token, { row, fields: new Map() });
        for (const column of group.columns.filter((c) => !keys.includes(c))) {
          const value = group.merged.find(
            (v) => JSON.stringify(v.row) === token && v.column === column,
          )?.value;
          rows.get(token).fields.set(column, value);
        }
      }
    const box = element("div");
    box.append(
      element(
        "p",
        "显式修复：每次显示前 12 条涉事记录。可删除记录或修改唯一字段；应用后继续处理剩余冲突。空字符串也参与唯一性比较。",
        "hint",
      ),
    );
    for (const { row, fields } of rows.values()) {
      const card = element("article", undefined, "conflict");
      card.append(element("h3", "修复记录 " + JSON.stringify(row)));
      const dropTarget = { row };
      const drop = element("input");
      drop.type = "checkbox";
      drop.setAttribute("aria-label", "删除唯一性记录：" + JSON.stringify(row));
      drop.checked =
        state.uniqueEdits.get(JSON.stringify(dropTarget))?.op === "set";
      drop.addEventListener("change", () =>
        uniqueDraft(
          { op: "set", target: dropTarget, choice: "drop" },
          drop.checked,
        ),
      );
      const label = element("label", undefined, "revoke");
      label.append(drop, document.createTextNode("明确删除整个记录"));
      card.append(label);
      for (const [column, value] of fields) {
        const target = { row, column };
        const draft = state.uniqueEdits.get(JSON.stringify(target));
        const check = element("input");
        check.type = "checkbox";
        check.checked = draft?.op === "set";
        check.setAttribute(
          "aria-label",
          "修正唯一字段：" + JSON.stringify(row) + " / " + column,
        );
        const text = element("textarea");
        text.rows = 2;
        text.value = draft?.choice?.value ?? value;
        text.setAttribute(
          "aria-label",
          "唯一值：" + JSON.stringify(row) + " / " + column,
        );
        text.disabled = !check.checked;
        const save = () => {
          text.disabled = !check.checked;
          uniqueDraft(
            { op: "set", target, choice: { value: text.value } },
            check.checked,
          );
        };
        check.addEventListener("change", save);
        text.addEventListener("input", save);
        const field = element("label");
        field.append(
          check,
          document.createTextNode(" 修正 " + column + "（保留精确文本）"),
          text,
        );
        card.append(field);
      }
      box.append(card);
    }
    return box;
  }
  function repairCard(repair) {
    const section = element("article", undefined, "conflict");
    section.append(
      element("h3", "唯一性修复 · " + targetText(repair.target)),
      sources(repair),
    );
    section.append(
      element(
        "p",
        repair.choice === "drop"
          ? "已明确删除整个记录"
          : "已填写明确值：" + JSON.stringify(repair.choice.value),
      ),
    );
    const token = JSON.stringify(repair.target);
    const draft = state.uniqueEdits.get(token);
    const check = element("input");
    check.type = "checkbox";
    check.checked = draft?.op === "revoke";
    check.setAttribute(
      "aria-label",
      "撤销唯一修复：" + targetText(repair.target),
    );
    check.addEventListener("change", () => {
      uniqueDraft({ op: "revoke", target: repair.target }, check.checked);
      if (text) text.disabled = check.checked;
    });
    const label = element("label", undefined, "revoke");
    label.append(check, document.createTextNode("明确撤销此唯一性修复"));
    let text = null;
    if (repair.choice !== "drop") {
      text = element("textarea");
      text.value = draft?.choice?.value ?? repair.choice.value;
      text.disabled = check.checked;
      text.setAttribute(
        "aria-label",
        "修改唯一值：" + targetText(repair.target),
      );
      text.addEventListener("input", () =>
        uniqueDraft(
          { op: "set", target: repair.target, choice: { value: text.value } },
          text.value !== repair.choice.value,
        ),
      );
      section.append(text);
    }
    section.append(label);
    return section;
  }
  function render() {
    const report = state.value.report;
    const pending = [
      ...report.conflicts,
      ...(report.unique_conflicts || []).map((group) => ({ unique: group })),
    ];
    const resolved = [
      ...report.resolutions,
      ...(report.unique_repairs || []).map((repair) => ({ repair })),
    ];
    const review = state.value.review.merge || state.value.review;
    $("session-rules").textContent = JSON.stringify(
      {
        key: review.key,
        row_order: review.row_order || "lexical",
        column_lineage: review.column_lineage || [],
        row_lineage: review.row_lineage || [],
        column_evolution: review.column_evolution || [],
        unique_rules: report.unique_rules || [],
      },
      null,
      2,
    );
    $("session-label").textContent = state.label;
    $("pending-count").textContent = pending.length;
    $("resolved-count").textContent = resolved.length;
    const structural = pending.some((c) =>
      ["ColumnDeleteEdit", "RowDeleteEdit", "ConcurrentInsert"].includes(
        c.kind,
      ),
    );
    $("phase-label").textContent = report.complete
      ? "可导出完整结果"
      : structural
        ? "先处理行列结构"
        : report.unique_conflicts?.length
          ? "处理唯一性冲突"
          : "处理单元格值";
    $("phase-label").classList.toggle("complete", report.complete);
    $("phase-note").textContent = report.complete
      ? "所有冲突已解决。仍可在已记录决策中修改或撤销，再次验证结果。"
      : structural
        ? "行列结构决策可能引出下一轮缺失值。选择删除会移除整个字段或记录，请查看各来源证据。"
        : report.unique_conflicts?.length
          ? "来源各自满足声明的唯一性规则，合并后出现重复。请显式修正涉事字段或删除记录；修复不得引入新的重复。已记录的修复须明确撤销。"
          : "空字符串是明确值；此来源无值表示缺失。请逐项决定，未选择的冲突会继续保留。";
    $("tab-pending").classList.toggle("active", state.tab === "pending");
    $("tab-resolved").classList.toggle("active", state.tab === "resolved");
    const items = state.tab === "pending" ? pending : resolved;
    const pages = Math.max(1, Math.ceil(items.length / PAGE));
    state.page = Math.min(state.page, pages - 1);
    const visible = items.slice(state.page * PAGE, (state.page + 1) * PAGE);
    const cards = visible.map((item) =>
      item.unique
        ? uniqueCard(item.unique)
        : item.repair
          ? repairCard(item.repair)
          : state.tab === "pending"
            ? card(item, null)
            : card(item.conflict, item),
    );
    $("conflicts").replaceChildren(
      ...(cards.length
        ? cards
        : [
            element(
              "div",
              state.tab === "pending"
                ? "当前没有待处理冲突。"
                : "尚未记录决策。",
              "blank",
            ),
          ]),
    );
    if (state.tab === "pending" && visible.some((item) => item.unique))
      $("conflicts").append(
        uniqueForms(
          visible.filter((item) => item.unique).map((item) => item.unique),
          review.key,
        ),
      );
    $("page-label").textContent =
      state.page + 1 + " / " + pages + " 页 · 共 " + items.length + " 项";
    $("previous").disabled = state.page === 0;
    $("next").disabled = state.page === pages - 1;
    $("export-status").textContent = report.complete
      ? "完整表格已就绪"
      : "可保存进度，表格导出暂未开放";
    $("result-note").textContent = report.complete
      ? "输出由同一 MoonBit 核心校验生成，包含所有保留的字段与记录。"
      : "所有冲突解决后开放导出，不生成部分结果。";
    $("download-csv").disabled = state.busy || !report.complete;
    $("download-tsv").disabled = state.busy || !report.complete;
    $("download-audit").disabled = !state.value.audit;
    $("audit-note").hidden = !state.value.audit;
    if (state.value.audit)
      $("audit-note").textContent =
        "本次应用记录了 " +
        state.value.audit.changes.length +
        " 项决策变更，完整前后证据可在下方下载。";
    updateApply();
  }
  function saveFile(name, text, type) {
    const blob = new Blob([text], { type });
    const link = element("a");
    const address = URL.createObjectURL(blob);
    link.href = address;
    link.download = name;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(address), 10000);
  }
  async function begin(resume) {
    const epoch = state.id;
    const texts = state.demo
      ? [state.demo.base, state.demo.ours, state.demo.theirs]
      : await Promise.all([
          read($("base-file").files[0], "共同祖先"),
          read($("ours-file").files[0], "当前版本"),
          read($("theirs-file").files[0], "另一版本"),
        ]);
    const continued = resume
      ? await read($("review-file").files[0], "审阅包")
      : "";
    if (epoch !== state.id) return;
    const args = [
      ...texts,
      $("format").value,
      $("keys").value,
      resume ? "lexical" : $("ordering").value,
      resume ? "[]" : $("columns").value,
      resume ? "[]" : $("rows").value,
      resume ? "[]" : $("evolution").value,
      continued,
    ];
    let result = await call("begin", args);
    if (!resume && $("unique-rules").value.trim() !== "[]")
      result = await call("unique", [
        JSON.stringify(result.review),
        $("unique-rules").value,
      ]);
    accept(
      result,
      state.demo
        ? "公开机场示例 · 模拟分支修改"
        : ["base", "ours", "theirs"]
            .map((side) => $(side + "-file").files[0].name)
            .join(" / "),
    );
  }
  $("begin").addEventListener("click", () => perform(() => begin(false)));
  $("replay-inputs").addEventListener("click", () =>
    perform(() => begin(true)),
  );
  $("open-review").addEventListener("click", () =>
    perform(async () => {
      const epoch = state.id;
      const file = $("review-file").files[0];
      const text = await read(file, "审阅包");
      if (epoch !== state.id) return;
      const result = await call("open", [text]);
      accept(result, "审阅包：" + file.name);
      $("keys").value = JSON.stringify(
        (result.review.merge || result.review).key,
      );
    }),
  );
  for (const side of ["base", "ours", "theirs"])
    $(side + "-file").addEventListener("change", () => {
      state.demo = null;
      $(side + "-name").textContent =
        $(side + "-file").files[0]?.name || "尚未选择文件";
    });
  for (const [id, key] of [
    ["demo-simple", "simple"],
    ["demo-evolution", "evolution"],
    ["demo-unique", "unique"],
  ])
    $(id).addEventListener("click", () =>
      perform(async () => {
        state.demo = demos[key];
        $("format").value = "csv";
        $("keys").value = '["id"]';
        $("ordering").value = "base";
        $("columns").value = "[]";
        $("rows").value = "[]";
        $("evolution").value = JSON.stringify(state.demo.evolution || []);
        $("unique-rules").value = JSON.stringify(state.demo.unique_rules || []);
        for (const side of ["base", "ours", "theirs"]) {
          $(side + "-file").value = "";
          $(side + "-name").textContent = "内置机场示例 · " + side;
        }
        await begin(false);
      }),
    );
  $("apply").addEventListener("click", () =>
    perform(async () => {
      if (state.edits.size && state.uniqueEdits.size)
        throw new Error(
          "普通决策和唯一性修复请分批应用。先明确撤销依赖的唯一性修复，再修改底层决策。",
        );
      if (!state.edits.size && !state.uniqueEdits.size)
        throw new Error("请先为冲突选择明确决策，或在已记录决策中勾选撤销。");
      const edits = [...state.edits.values()].map((draft) =>
        draft.revoke
          ? { op: "revoke", target: draft.target }
          : { op: "set", target: draft.target, choice: draft.choice },
      );
      const result = await call(state.uniqueEdits.size ? "repair" : "update", [
        JSON.stringify(state.value.review),
        JSON.stringify(
          state.uniqueEdits.size ? [...state.uniqueEdits.values()] : edits,
        ),
      ]);
      accept(result, state.label);
    }),
  );
  for (const tab of ["pending", "resolved"])
    $("tab-" + tab).addEventListener("click", () => {
      state.tab = tab;
      state.page = 0;
      render();
    });
  $("previous").addEventListener("click", () => {
    state.page--;
    render();
  });
  $("next").addEventListener("click", () => {
    state.page++;
    render();
  });
  $("download-review").addEventListener("click", () =>
    saveFile(
      "review.json",
      JSON.stringify(state.value.review, null, 2) + "\n",
      "application/json;charset=utf-8",
    ),
  );
  $("download-report").addEventListener("click", () =>
    saveFile(
      "evidence.json",
      JSON.stringify(state.value.report, null, 2) + "\n",
      "application/json;charset=utf-8",
    ),
  );
  $("download-audit").addEventListener("click", () =>
    saveFile(
      "review-changes.json",
      JSON.stringify(state.value.audit, null, 2) + "\n",
      "application/json;charset=utf-8",
    ),
  );
  for (const format of ["csv", "tsv"])
    $("download-" + format).addEventListener("click", () =>
      perform(async () => {
        const result = await call("export", [
          JSON.stringify(state.value.review),
          format,
        ]);
        saveFile(
          "merged." + format,
          result.text,
          (format === "csv" ? "text/csv" : "text/tab-separated-values") +
            ";charset=utf-8",
        );
      }),
    );
  $("cancel").addEventListener("click", () => {
    state.operation++;
    state.id++;
    state.worker.terminate();
    if (waiter) {
      waiter.reject(new Error("已取消，之前的审阅状态仍保留。"));
      waiter = null;
    }
    spawn();
    busy(false);
    error(new Error("已取消，之前的审阅状态仍保留。"));
  });
  try {
    spawn();
  } catch (e) {
    error(new Error("无法启动本地处理线程：" + e.message));
    $("begin").disabled = true;
  }
})();
