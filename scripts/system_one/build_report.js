const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, ImageRun,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle, LevelFormat,
  Footer, PageNumber, TabStopType,
} = require("docx");

const ROOT = require("path").resolve(__dirname, "../..");
const FIG = path.join(ROOT, "results/SystemOne/figures");
const OUT = path.join(ROOT, "results/SystemOne/Jev_Annotation_Report.docx");

const FONT = "Calibri";
const ACCENT = "C0500E";
const CONTENT_W = 9360; // 6.5in in DXA

// ---------- helpers
const t = (text, o = {}) => new TextRun({ text, font: FONT, ...o });
const p = (runs, o = {}) => new Paragraph({
  children: typeof runs === "string" ? [t(runs)] : runs,
  spacing: { after: 120, line: 276 }, ...o,
});
const h1 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [t(text)] });
const h2 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [t(text)] });
const bullet = (runs) => new Paragraph({
  numbering: { reference: "bullets", level: 0 },
  children: typeof runs === "string" ? [t(runs)] : runs,
  spacing: { after: 80, line: 276 },
});
const b = (text) => t(text, { bold: true });

function figure(file, wPx, hPx, num, caption) {
  const width = 624; // 6.5in at 96 dpi
  const w = Math.round(wPx * (width / wPx) * (wPx > hPx ? 1 : 0.7));
  const h = Math.round(hPx * (w / wPx));
  return [
    new Paragraph({
      alignment: AlignmentType.CENTER, spacing: { before: 120, after: 60 },
      children: [new ImageRun({ type: "jpg", data: fs.readFileSync(path.join(FIG, file)),
        transformation: { width: w, height: h },
        altText: { title: `Figure ${num}`, description: caption, name: `fig${num}` } })],
    }),
    new Paragraph({
      spacing: { after: 240 },
      children: [t(`Figure ${num}. `, { bold: true, size: 19 }), t(caption, { size: 19, color: "404040" })],
    }),
  ];
}

const border = { style: BorderStyle.SINGLE, size: 4, color: "BFBFBF" };
const borders = { top: border, bottom: border, left: border, right: border };

function table(headers, rows, widths, opts = {}) {
  const total = widths.reduce((a, c) => a + c, 0);
  const cell = (text, w, { header = false, bold = false, fill } = {}) => new TableCell({
    width: { size: w, type: WidthType.DXA }, borders,
    shading: header ? { fill: "F2F2F2", type: ShadingType.CLEAR, color: "auto" }
      : fill ? { fill, type: ShadingType.CLEAR, color: "auto" } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    children: [new Paragraph({
      alignment: header || typeof text !== "string" || /^[\d+\-−.<(\[]/.test(text) ? AlignmentType.CENTER : AlignmentType.LEFT,
      children: [t(String(text), { bold: header || bold, size: 19 })],
    })],
  });
  return new Table({
    width: { size: total, type: WidthType.DXA }, columnWidths: widths,
    rows: [
      new TableRow({ tableHeader: true, children: headers.map((hh, i) => cell(hh, widths[i], { header: true })) }),
      ...rows.map((r) => new TableRow({
        children: r.map((c, i) => cell(c, widths[i], {
          bold: opts.boldRow && opts.boldRow(r), fill: opts.fillRow && opts.fillRow(r),
        })),
      })),
    ],
  });
}
const tableCaption = (num, text) => new Paragraph({
  spacing: { before: 200, after: 80 }, keepNext: true,
  children: [t(`Table ${num}. `, { bold: true, size: 19 }), t(text, { size: 19, color: "404040" })],
});
const spacer = () => new Paragraph({ spacing: { after: 120 }, children: [] });

// ---------- content
const jevFill = (r) => (String(r[0]).startsWith("Jev") ? "FCE9DC" : undefined);

const children = [
  new Paragraph({ spacing: { after: 60 }, children: [t("DRAFT — for internal discussion", { size: 18, color: ACCENT, bold: true })] }),
  new Paragraph({ heading: HeadingLevel.TITLE, children: [t("Can Jev annotate classroom Talk Moves?")] }),
  new Paragraph({ spacing: { after: 60 }, children: [t("TypeSafe AI's System One model compared with six frontier LLMs on the Talk Moves baseline", { size: 26, color: "595959" })] }),
  new Paragraph({ spacing: { after: 360 }, children: [t("National Tutoring Observatory · Baseline Performance Pipeline · 25 October 2026", { size: 20, color: "7F7F7F" })] }),

  h1("Summary"),
  p("We ran Jev (typesafe/jev-1.14-20261014), a model that returns a probability for each label instead of generated text, on the Talk Moves annotation task from our baseline paper. We used the same chunks, prompts, ground truth and scoring as the paper and compared Jev with the paper's six LLMs on 9,270 held-out teacher utterances."),
  bullet([b("Jev agrees with human coders less well than the LLMs. "), t("Its 7-class κ ranges from 0.38 (ZeroShot) to 0.48 (FewShot_ALL). It ranks last of seven models in three prompt conditions and sixth in FewShot_ALL, where it beats o3. Its best κ (0.48) is roughly where the LLMs start at ZeroShot (0.38–0.48).")]),
  bullet([b("Examples help Jev a lot. "), t("κ rises by +0.10 from ZeroShot to FewShot_ALL (p < .001), which goes against outside reports that Jev does not learn from in-context examples.")]),
  bullet([b("Its biggest gaps are the comparison codes. "), t("On Restating and Revoicing, where the coder has to judge whether the teacher repeated a student, Jev's per-code κ is 0.14–0.25 below the LLM average (FewShot_ALL). With full examples it is level with the LLMs on Pressing for Accuracy and Keeping Everyone Together.")]),
  bullet([b("Its probabilities are useful but overconfident. "), t("Confidence separates right from wrong labels (AUROC 0.73–0.76), and its most confident quarter of labels is 87–92% correct. Average confidence still exceeds accuracy by 6–10 points, mostly because it gives too little probability to “None”.")]),
  bullet([b("It is cheap and fast. "), t("The entire study, about 4,900 requests, cost $1.81. Median latency was 0.22–0.27 s per chunk.")]),
  p([b("Bottom line: "), t("Jev cannot yet replace an LLM as a primary annotator for this scheme. Its cheap, well-ranked confidence makes it a candidate for triage: let it auto-label the utterances it is sure of and send the rest to an LLM or a human. That use still needs to be tested with recalibrated probabilities (see Next steps).")], { spacing: { before: 120, after: 200 } }),

  h1("What we tested"),
  p("The task, data and metrics are unchanged from the baseline paper. Each teacher utterance gets one of six Talk Moves or None, scored against human ground truth."),
  bullet([b("Data. "), t("The paper's 467 stratified chunks (60 transcripts, 10,535 teacher utterances). Before any full run we set aside 6 transcripts (58 chunks) as a development set for design decisions. All results here come from the remaining 54 transcripts: 409 chunks and 9,270 teacher utterances.")]),
  bullet([b("How Jev was asked. "), t("Like the LLMs, Jev saw one whole chunk per request, as JSON dialogue. Each request asked one multiple-choice question per teacher utterance, with seven options: the six moves, described with the coding-manual definitions, plus None. Jev answers each question separately, so one utterance's label cannot depend on its neighbours' labels; the LLMs, which wrote out one list for the whole chunk, could do that.")]),
  bullet([b("Prompt conditions. "), t("ZeroShot, OneShot, FewShot_3 and FewShot_ALL, using the paper's prompt files. In a development-set pilot, examples worked slightly better in the question text than in the shared dialogue context (mean κ 0.449 vs. 0.435), so all few-shot runs put them there.")]),
  bullet([b("Statistics. "), t("These match the paper: 7-class Cohen's κ, macro F1 and per-code binary κ; 95% percentile CIs from 1,000 utterance-level bootstrap resamples; paired bootstrap tests on shared utterances. Each LLM is scored on the predictions it returned, as in the paper. For FewShot_ALL that is 81% of utterances for Opus and 87% for Gemini 3 Pro; Jev returned every prediction.")]),

  h1("How well does Jev agree with human coders?"),
  ...figure("overall_kappa.jpg", 2400, 800, 1, "7-class Cohen's κ against human labels for Jev 1.14 (orange) and the six LLMs (grey), by prompt condition. Bars are 95% bootstrap CIs."),
  tableCaption(1, "Agreement with human labels on the evaluation set (7-class Cohen's κ with 95% CI). Rank is Jev's position among the seven models."),
  table(
    ["Prompt", "Jev 1.14 κ", "LLM range κ", "Best LLM", "Jev rank", "Jev − best LLM"],
    [
      ["ZeroShot", "0.377 [0.362, 0.390]", "0.380 – 0.482", "Claude 4.5 Opus", "7 of 7", "−0.106"],
      ["OneShot", "0.425 [0.411, 0.438]", "0.436 – 0.485", "Opus / GPT-5", "7 of 7", "−0.060"],
      ["FewShot_3", "0.440 [0.426, 0.454]", "0.474 – 0.542", "Claude 4.5 Opus", "7 of 7", "−0.102"],
      ["FewShot_ALL", "0.476 [0.462, 0.491]", "0.450 – 0.578", "Claude 4.5 Opus", "6 of 7", "−0.106"],
    ],
    [1500, 1900, 1500, 1700, 1100, 1660],
  ),
  spacer(),
  p("In paired tests, Jev is significantly below Opus, Gemini 3 Pro and GPT-5 in every condition (p ≤ .01). Against the other three LLMs:"),
  bullet("It is statistically level with Gemini 2.5 Pro at ZeroShot (Δκ = −0.004, p = .62) and with Claude 4.5 Sonnet at OneShot (Δκ = −0.011, p = .07)."),
  bullet("It is significantly above o3 at FewShot_ALL (Δκ = +0.026, p < .001), where o3 gets worse with more examples."),
  p("Version 1.14 beats 1.13, the version used in early outside evaluations, by +0.015 κ (p < .001). The two versions agree on 91% of labels."),

  h2("Examples matter more than expected"),
  p("Outside evaluations reported that Jev does not learn domain categories from in-context examples. We found the opposite: each added block of examples raised κ significantly (Table 2). The FewShot_ALL gain (+0.10) matches the largest LLM gain in the paper (Claude 4.5 Opus, +0.11); most LLMs gained much less."),
  tableCaption(2, "Change in Jev's κ between prompt conditions (paired bootstrap, 95% CI)."),
  table(
    ["Comparison", "Δκ", "95% CI", "p"],
    [
      ["OneShot − ZeroShot", "+0.049", "[+0.041, +0.057]", "< .001"],
      ["FewShot_3 − ZeroShot", "+0.064", "[+0.055, +0.072]", "< .001"],
      ["FewShot_ALL − ZeroShot", "+0.100", "[+0.088, +0.112]", "< .001"],
      ["FewShot_ALL − FewShot_3", "+0.036", "[+0.025, +0.048]", "< .001"],
    ],
    [3600, 1700, 2560, 1500],
  ),

  h1("Where Jev goes wrong"),
  ...figure("per_code_kappa.jpg", 2800, 900, 2, "Per-code binary κ (one move vs. all others) with 95% CIs. Jev 1.14 in orange; the six LLMs in grey."),
  tableCaption(3, "Per-code binary κ in the FewShot_ALL condition: Jev vs. the LLMs."),
  table(
    ["Talk Move", "Jev 1.14", "LLM mean", "LLM range", "Jev − LLM mean"],
    [
      ["Keeping Everyone Together", "0.392", "0.380", "0.302 – 0.461", "+0.012"],
      ["Relating to Another's Ideas", "0.579", "0.627", "0.531 – 0.707", "−0.048"],
      ["Restating", "0.385", "0.637", "0.570 – 0.721", "−0.252"],
      ["Revoicing", "0.218", "0.361", "0.291 – 0.411", "−0.143"],
      ["Pressing for Accuracy", "0.610", "0.633", "0.577 – 0.660", "−0.023"],
      ["Pressing for Reasoning", "0.335", "0.372", "0.272 – 0.408", "−0.037"],
      ["None", "0.526", "0.590", "0.508 – 0.661", "−0.064"],
    ],
    [3060, 1350, 1350, 1900, 1700],
    { fillRow: (r) => (["Restating", "Revoicing"].includes(r[0]) ? "FCE9DC" : undefined) },
  ),
  spacer(),
  p("The weakest codes are Restating and Revoicing. Telling them apart means judging whether the teacher repeated a student word for word or changed the wording. Outside evaluations named this kind of earlier-turn comparison as a weak spot for Jev, and our results agree. The confusion matrix (Figure 3) shows the pattern:"),
  bullet("26% of true Revoicing utterances are labelled Restating, against 17% for Claude 4.5 Opus in the paper's matching figure (full sample)."),
  bullet("Jev labels Restating too often overall. Its predictions include many teacher utterances that humans coded as None."),
  bullet("The other main confusion is the one the paper reported for the LLMs: Pressing for Accuracy labelled as Pressing for Reasoning (14–30%, depending on the prompt)."),
  ...figure("confusion_jev_FewShot_ALL.jpg", 2000, 1750, 3, "Jev 1.14 confusion matrix, FewShot_ALL, evaluation set. Each cell is the percentage of that human-label row; the diagonal is correct."),

  h1("Can Jev's probabilities be trusted?"),
  p("Unlike the LLMs, Jev returns a probability for every option, so we can check whether its confidence tracks its accuracy. Everything in this section uses Jev's raw, unrecalibrated probabilities, measured against the human labels."),
  ...figure("reliability_jev.jpg", 2600, 780, 4, "Reliability of Jev's confidence in the label it chose. Points below the dashed line mean Jev was overconfident; point size is the number of utterances in each bin."),
  tableCaption(4, "Calibration of Jev 1.14 against human labels (evaluation set, raw probabilities)."),
  table(
    ["Prompt", "Accuracy", "Mean confidence", "ECE [95% CI]", "AUROC", "Share ≥ 0.9 conf.", "Error when ≥ 0.9"],
    [
      ["ZeroShot", "0.639", "0.732", "0.095 [0.087, 0.104]", "0.746", "30%", "12.7%"],
      ["OneShot", "0.683", "0.781", "0.099 [0.092, 0.108]", "0.755", "42%", "12.3%"],
      ["FewShot_3", "0.683", "0.755", "0.073 [0.066, 0.082]", "0.752", "34%", "11.1%"],
      ["FewShot_ALL", "0.671", "0.729", "0.061 [0.054, 0.071]", "0.730", "28%", "13.4%"],
    ],
    [1360, 1100, 1300, 1900, 1000, 1350, 1350],
  ),
  spacer(),
  bullet([b("Confidence ranks errors well. "), t("Higher confidence means steadily higher accuracy (Figure 4), and confidence tells right from wrong labels with AUROC 0.73–0.76. Within each code the ranking is very strong: AUROC 0.97–0.99 for Relate, Restating and Reasoning.")]),
  bullet([b("It is overconfident by 6–10 points. "), t("Most of this comes from too little probability on None. In FewShot_ALL, None gets an average probability of 0.44, but 67% of utterances are None. The rare moves get too much: Restating averages 0.056 against a true rate of 1.2%. A miscalibration this regular is what simple temperature or per-class recalibration usually fixes.")]),
  bullet([b("Hard items are hard for everyone. "), t("Jev is also wrong on about 95% of the utterances that all six LLMs got wrong. Its confidence on them is lower (median 0.69–0.74 vs. 0.75–0.86, p < .05) but still not low enough to flag them reliably.")]),
  ...figure("reliability_per_code.jpg", 2200, 1320, 5, "Per-code reliability (one move vs. all others). For each code, Jev's probability for that code against the share of utterances humans gave that code, by prompt condition. Above the dashed line Jev under-predicts the code; below it, Jev over-predicts."),
  p("Breaking calibration down by code (Figure 5) shows three different patterns:"),
  bullet([b("Close to calibrated: "), t("Pressing for Accuracy and Relating to Another's Ideas. Jev's probabilities can be read roughly at face value.")]),
  bullet([b("Over-predicted until very high probability: "), t("Restating, Revoicing and Pressing for Reasoning. Below about 0.8, humans rarely gave the code, however much probability Jev assigned. Only Jev's top bin, near 1.0, means much, and even there Revoicing and Reasoning are right only 35–55% of the time. This matches the Restating/Revoicing confusions in Figure 3.")]),
  bullet([b("Under-predicted: "), t("None. Whatever probability Jev gives None, humans chose None more often, which is the main source of the overall overconfidence. Keeping Everyone Together is nearly flat, so its probability carries little information except in FewShot_ALL.")]),
  p("Because each code fails in its own direction, a single global temperature will not fix these errors; per-class recalibration is needed."),
  ...figure("risk_coverage.jpg", 2600, 840, 6, "Accuracy of the labels kept when only the most confident utterances are kept. Orange: Jev's own confidence. Grey: agreement among the six LLMs (share giving the modal label)."),
  p([b("Triage potential. "), t("Figure 6 compares Jev's confidence with the strongest confidence signal available from the LLMs, which is how many of the six agree.")]),
  bullet("Jev's most confident 25% of utterances are 87–92% correct, and its most confident half 81–85%."),
  bullet("When all six LLMs agree (47–72% of utterances, depending on the prompt), the label is 84–90% correct."),
  p("So a single cheap Jev call gives a usable confidence signal for its best quarter of utterances, but beyond about half the utterances six-LLM agreement is more accurate."),

  h1("Stability, versions and cost"),
  tableCaption(5, "Robustness checks on 50 evaluation chunks (1,158 utterances), ZeroShot."),
  table(
    ["Check", "Labels that change", "Mean shift in probability", "κ (vs. 0.345 original)"],
    [
      ["Identical request repeated (×5)", "3.3 – 3.7%", "0.02", "0.337 – 0.346"],
      ["Option order shuffled", "7.7%", "0.05", "0.342"],
      ["Options renamed A–G (definitions kept)", "17.1%", "0.11", "0.353"],
    ],
    [3600, 1800, 2100, 1860],
  ),
  spacer(),
  bullet([b("Not fully deterministic. "), t("Sending identical requests again changes about 3–4% of labels. A same-version repeat on a separate day is scheduled to measure this on the full set.")]),
  bullet([b("Sensitive to how options are presented. "), t("Shuffling the option order changes 8% of labels, and hiding the move names behind letters changes 17%. Overall κ barely moves, so these changes look like noise on borderline items rather than a systematic bias, but it is a reason to fix the option order and wording across studies.")]),
  bullet([b("Cost and speed. "), t("The full replication (four prompt conditions × 467 chunks, about 24.2M input tokens) cost $1.01. Everything in this study, including the pilot, decomposition and robustness runs, cost $1.81. Median latency was 0.22–0.27 s per chunk request; p95 was at most 0.50 s.")]),

  h1("Implications for annotation"),
  bullet([b("Not a drop-in replacement. "), t("Using the same prompts, Jev is about 0.05–0.10 κ behind the best LLMs and weakest exactly where the scheme needs a comparison with earlier turns (Restating vs. Revoicing).")]),
  bullet([b("A strong candidate for first-pass triage. "), t("Its probabilities are cheap, rank errors well, and are systematically rather than randomly off. A workflow where Jev auto-labels high-confidence utterances and sends the rest on looks feasible; the confidence-gating analysis will test it directly.")]),
  bullet([b("Ask simpler questions. "), t("Outside work suggests Jev does much better when one broad question is split into several narrow yes/no questions. We have already collected 12 such per-utterance yes/no answers from Jev (Condition B), along with plain string-matching features for word-for-word repetition. Restating vs. Revoicing may be better handled by a string comparison than by asking Jev.")]),

  h1("Limitations"),
  bullet("Jev labels each utterance separately; the LLMs labelled a whole chunk in one response. Some of the gap may come from the request format rather than the model. A check on the development set found that per-chunk and per-utterance requests to Jev agree on 97% of labels."),
  bullet("Jev is proprietary and unpublished, and its training data are unknown. Its probabilities may be calibrated to LLM consensus rather than to human coders, and results are specific to these model versions."),
  bullet("LLM results are reused from the paper's runs and include its missing outputs (Opus FewShot_ALL returned 81% of utterances). The missing chunks were not harder for Jev or the other LLMs, so this is unlikely to bias the comparison."),
  bullet("Following the paper, CIs resample utterances. Utterances within a lesson are correlated, so these intervals describe this sample of lessons. Transcript-level intervals would be about 1.4–2.4× wider."),

  h1("Next steps"),
  bullet("Recalibrate Jev's probabilities within transcript folds and re-measure calibration. Figure 5 suggests per-class recalibration (for example, a per-code bias on None and the comparison codes) will do much better than one global temperature."),
  bullet("Confidence-gated automation: choose thresholds for 5% and 10% target error and report how many utterances could be auto-labelled."),
  bullet("Decomposition (Condition B): compare the 12 per-utterance yes/no questions and the string-matching features with direct labelling, especially on Restating vs. Revoicing."),
  bullet("Same-version repeat of the full ZeroShot run on a separate day, to measure run-to-run noise."),

  new Paragraph({ spacing: { before: 360 }, border: { top: { style: BorderStyle.SINGLE, size: 4, color: "BFBFBF", space: 6 } },
    children: [t("Reproducibility. ", { bold: true, size: 18, color: "595959" }), t("Code, configuration and the pre-registered analysis plan are in scripts/system_one/, config/system_one_config.yaml and results/SystemOne/ANALYSIS_PLAN.md on branch system-one-replication. Tables are in results/SystemOne/. Raw Jev requests and responses are logged under data/outputs/SystemOne_Jev_Von/.", { size: 18, color: "595959" })] }),
];

const doc = new Document({
  creator: "National Tutoring Observatory",
  title: "Can Jev annotate classroom Talk Moves?",
  styles: {
    default: { document: { run: { font: FONT, size: 22 } } },
    paragraphStyles: [
      { id: "Title", name: "Title", basedOn: "Normal", next: "Normal",
        run: { font: FONT, size: 44, bold: true, color: "1F1F1F" }, paragraph: { spacing: { after: 80 } } },
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 30, bold: true, color: ACCENT }, paragraph: { spacing: { before: 320, after: 120 }, outlineLevel: 0, keepNext: true } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 25, bold: true, color: "333333" }, paragraph: { spacing: { before: 240, after: 100 }, outlineLevel: 1, keepNext: true } },
    ],
  },
  numbering: { config: [{ reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
    style: { paragraph: { indent: { left: 540, hanging: 270 } } } }] }] },
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({
      tabStops: [{ type: TabStopType.RIGHT, position: CONTENT_W }],
      children: [t("Jev Talk Moves report — draft", { size: 16, color: "7F7F7F" }), t("\tPage ", { size: 16, color: "7F7F7F" }),
        new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 16, color: "7F7F7F" })],
    })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => { fs.writeFileSync(OUT, buf); console.log("wrote", OUT); });
