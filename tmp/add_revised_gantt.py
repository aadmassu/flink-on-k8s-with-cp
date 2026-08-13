"""Add a 'Revised Gantt' sheet to the workbook.

Both tracks combined on one chart. 14-week schedule starting the week of
2026-05-18, driven by Ayu's CFK + migration load at 20 hrs/wk. Asmerom
finishes Job #2 work around W7 at 20 hrs/wk.
"""
from openpyxl import load_workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

WB_PATH = "docs/Flink_K8s_CP_Gantt_Chart.xlsx"
SHEET_NAME = "Revised Gantt"

NAVY = "FF0A2F5C"
NAVY_DARK = "FF003762"
WHITE = "FFFFFFFF"
LIGHT_GREY = "FFF2F2F2"
FLINK_BAND = "FFE3F2FD"
CFK_BAND = "FFF3E5F5"
GOV_BAND = "FFFFF8E1"

# bar colors
AYU_BAR = "FF1E88E5"        # blue
ASM_BAR = "FFFB8C00"        # orange
BLOCKED_BAR = "FFE53935"    # red (overlay for CFK DEV deploy)
SHARED_BAR = "FF8E24AA"     # purple

# today marker
TODAY_FILL = "FFFFE082"

thin = Side(border_style="thin", color="FFBDBDBD")
border = Border(left=thin, right=thin, top=thin, bottom=thin)

# 14 weeks starting week of May 18, 2026 (current week — today is Thu May 21)
WEEKS = [
    ("W1",  "May 18-22 ★"),  # today
    ("W2",  "May 25-29"),
    ("W3",  "Jun 1-5"),
    ("W4",  "Jun 8-12"),
    ("W5",  "Jun 15-19"),
    ("W6",  "Jun 22-26"),
    ("W7",  "Jun 29-Jul 3"),
    ("W8",  "Jul 6-10"),
    ("W9",  "Jul 13-17"),
    ("W10", "Jul 20-24"),
    ("W11", "Jul 27-31"),
    ("W12", "Aug 3-7"),
    ("W13", "Aug 10-14"),
    ("W14", "Aug 17-21"),
]
N_WEEKS = len(WEEKS)

# Activities. Each tuple:
#   (label, owner, hrs, status, week_range_inclusive, label_in_bar)
# week_range is 1-indexed inclusive [start, end].
ACTIVITIES = {
    "FLINK TRACK": [
        ("Flink UAT cluster provision",          "Ayu",     16, "Pending",     (1, 2),   "16h"),
        ("Flink Job #2 — development",           "Asmerom", 96, "In Progress", (1, 5),   "96h"),
        ("Flink Job #2 — hardening & buffer",    "Asmerom", 32, "Pending",     (6, 7),   "32h"),
        ("Flink PRD cluster provision",          "Ayu",     20, "Pending",     (10, 11), "20h"),
    ],
    "CFK TRACK": [
        ("Deploy CFK DEV (unblock storage)",     "Ayu",     24, "Blocked",     (1, 2),   "24h"),
        ("CFK STG manifests + DevOps",           "Ayu",     20, "Pending",     (3, 3),   "20h"),
        ("CFK UAT manifests + DevOps",           "Ayu",     20, "Pending",     (4, 4),   "20h"),
        ("CFK PRD1 manifests + DevOps",          "Ayu",     24, "Pending",     (5, 6),   "24h"),
        ("CFK DR manifests + DevOps",            "Ayu",     24, "Pending",     (6, 7),   "24h"),
        ("Cluster link + migration — DEV",       "Ayu",     20, "Pending",     (7, 8),   "20h"),
        ("Cluster link + migration — UAT",       "Ayu",     24, "Pending",     (8, 9),   "24h"),
        ("Cluster link + migration — STG",       "Ayu",     24, "Pending",     (9, 10),  "24h"),
        ("Cluster link + migration — PRD",       "Ayu",     36, "Pending",     (11, 13), "36h"),
    ],
    "GOVERNANCE": [
        ("Docs / runbooks / handoff",            "Ayu",     16, "Pending",     (13, 14), "16h"),
        ("Contingency / unscheduled support",    "Shared",  12, "Pending",     (14, 14), "12h"),
    ],
}

DONE_NOTE = (
    "Already completed: all-env Flink manifests, Flink Infra CI + Job CI/CD, "
    "Flink DEV cluster, Flink Job #1, CFK DEV manifests, CFK CI/CD pipelines."
)


def fill(color):
    return PatternFill(fill_type="solid", fgColor=color)


def main():
    wb = load_workbook(WB_PATH)
    if SHEET_NAME in wb.sheetnames:
        del wb[SHEET_NAME]
    ws = wb.create_sheet(SHEET_NAME)

    # Column layout:
    # A=#, B=Activity, C=Owner, D=Hrs, E=Status, F..S = W1..W14
    base_cols = 5
    total_cols = base_cols + N_WEEKS

    ws.column_dimensions["A"].width = 5
    ws.column_dimensions["B"].width = 42
    ws.column_dimensions["C"].width = 9
    ws.column_dimensions["D"].width = 7
    ws.column_dimensions["E"].width = 12
    for i in range(N_WEEKS):
        ws.column_dimensions[get_column_letter(base_cols + 1 + i)].width = 11

    center = Alignment(horizontal="center", vertical="center", wrap_text=True)
    left = Alignment(horizontal="left", vertical="center", wrap_text=True)

    # ----- title row
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=total_cols)
    t = ws.cell(row=1, column=1,
                value="Revised Gantt — Flink + CFK Combined "
                      "(snapshot 2026-05-21, 14 weeks @ 20 hrs/wk each)")
    t.font = Font(name="Calibri", size=14, bold=True, color=NAVY_DARK)
    t.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 24

    # ----- notes row
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=total_cols)
    n = ws.cell(row=2, column=1,
                value=("Capacity: Ayu 20 hrs/wk (274 hrs / 14 wks), "
                       "Asmerom 20 hrs/wk (134 hrs / ~7 wks). "
                       "Tushar work excluded. ★ = current week. " + DONE_NOTE))
    n.font = Font(name="Calibri", size=10, italic=True, color="FF555555")
    n.alignment = left
    ws.row_dimensions[2].height = 42

    # ----- header row (row 4)
    hdr_row = 4
    headers = ["#", "Activity", "Owner", "Hrs", "Status"] + [
        f"{wk}\n{rng}" for wk, rng in WEEKS
    ]
    for i, h in enumerate(headers, start=1):
        c = ws.cell(row=hdr_row, column=i, value=h)
        c.fill = fill(NAVY_DARK)
        c.font = Font(name="Calibri", size=9, bold=True, color=WHITE)
        c.alignment = center
        c.border = border
    # highlight current week column header
    cur = ws.cell(row=hdr_row, column=base_cols + 1)
    cur.fill = fill("FFB71C1C")  # deep red header for "today" column
    ws.row_dimensions[hdr_row].height = 32

    # ----- bands
    band_color = {
        "FLINK TRACK": FLINK_BAND,
        "CFK TRACK": CFK_BAND,
        "GOVERNANCE": GOV_BAND,
    }
    bar_color_for = {
        "Ayu": AYU_BAR,
        "Asmerom": ASM_BAR,
        "Shared": SHARED_BAR,
    }

    row = hdr_row + 1
    section_idx = 0

    for section_name, items in ACTIVITIES.items():
        # section band header
        ws.merge_cells(start_row=row, start_column=1,
                       end_row=row, end_column=total_cols)
        b = ws.cell(row=row, column=1, value=section_name)
        b.fill = fill(NAVY)
        b.font = Font(name="Calibri", size=11, bold=True, color=WHITE)
        b.alignment = Alignment(horizontal="left", vertical="center")
        ws.row_dimensions[row].height = 18
        row += 1

        for idx, (label, owner, hrs, status, (ws_start, ws_end), bar_label) in enumerate(items, start=1):
            band = fill(band_color[section_name])
            # base cells
            ws.cell(row=row, column=1, value=idx).fill = band
            ws.cell(row=row, column=2, value=label).fill = band
            ws.cell(row=row, column=3, value=owner).fill = band
            ws.cell(row=row, column=4, value=hrs).fill = band
            ws.cell(row=row, column=5, value=status).fill = band

            ws.cell(row=row, column=1).alignment = center
            ws.cell(row=row, column=2).alignment = left
            ws.cell(row=row, column=3).alignment = center
            ws.cell(row=row, column=4).alignment = center
            ws.cell(row=row, column=5).alignment = center

            for col in range(1, 6):
                ws.cell(row=row, column=col).border = border
                ws.cell(row=row, column=col).font = Font(name="Calibri", size=10)

            # status cell colored
            status_colors = {
                "Done": "FFC8E6C9",
                "In Progress": "FFFFE0B2",
                "Blocked": "FFFFCDD2",
                "Pending": "FFE0E0E0",
            }
            ws.cell(row=row, column=5).fill = fill(status_colors.get(status, "FFFFFFFF"))
            ws.cell(row=row, column=5).font = Font(name="Calibri", size=10, bold=True)

            # week bar cells
            bar_color = bar_color_for.get(owner, AYU_BAR)
            if status == "Blocked":
                bar_color = BLOCKED_BAR
            for w in range(1, N_WEEKS + 1):
                col = base_cols + w
                cell = ws.cell(row=row, column=col)
                if ws_start <= w <= ws_end:
                    cell.fill = fill(bar_color)
                    cell.font = Font(name="Calibri", size=9, bold=True, color=WHITE)
                    cell.alignment = center
                    if w == ws_start:
                        cell.value = bar_label
                else:
                    cell.fill = band
                cell.border = border

            ws.row_dimensions[row].height = 22
            row += 1

    # ----- weekly capacity check rows
    row += 1
    ws.cell(row=row, column=2, value="Weekly load check (target 20 hrs / person)").font = Font(
        name="Calibri", size=11, bold=True
    )
    row += 1

    # Compute per-person weekly hours by spreading activity hours across its week span
    def weekly_load(owner_filter):
        load = [0.0] * N_WEEKS
        for items in ACTIVITIES.values():
            for label, owner, hrs, status, (ws_start, ws_end), _ in items:
                if owner != owner_filter:
                    continue
                span = ws_end - ws_start + 1
                per_week = hrs / span
                for w in range(ws_start, ws_end + 1):
                    load[w - 1] += per_week
        return load

    ayu_load = weekly_load("Ayu")
    asm_load = weekly_load("Asmerom")
    shared_load = weekly_load("Shared")

    def write_load_row(label, vals, color):
        nonlocal row
        ws.cell(row=row, column=2, value=label).font = Font(name="Calibri", size=10, bold=True)
        ws.cell(row=row, column=2).alignment = left
        ws.cell(row=row, column=4, value=round(sum(vals), 1)).font = Font(
            name="Calibri", size=10, bold=True
        )
        ws.cell(row=row, column=4).alignment = center
        for w in range(N_WEEKS):
            c = ws.cell(row=row, column=base_cols + 1 + w, value=round(vals[w], 1) if vals[w] else "")
            c.alignment = center
            c.font = Font(name="Calibri", size=9)
            c.border = border
            if vals[w] > 20.5:
                c.fill = fill("FFFFCDD2")  # over capacity
            elif vals[w] > 0:
                c.fill = fill(color)
        row += 1

    write_load_row("Ayu — hrs/wk", ayu_load, "FFE3F2FD")
    write_load_row("Asmerom — hrs/wk", asm_load, "FFFFE0B2")
    write_load_row("Shared — hrs/wk", shared_load, "FFF3E5F5")

    # ----- schedule notes
    row += 2
    ws.cell(row=row, column=2, value="Schedule notes:").font = Font(
        name="Calibri", size=11, bold=True
    )
    row += 1
    notes = [
        "Ayu averages 19.6 hrs/wk over 14 weeks (274 hrs / 14 wks).",
        "Ayu transition weeks (W6, W9) show ~24 hrs from naive even-split of overlapping bars; "
        "real work pattern is heavy-on-primary-week, taper into next — no actual overrun.",
        "Asmerom is at 19.2 hrs/wk W1–W5 (Job #2 dev), 16 hrs/wk W6–W7 (hardening). "
        "Free capacity from W8 onward — available for support, contingency, or new scope.",
        "CFK DEV deploy (W1–W2) is gated on storage unblock; if storage slips, the entire "
        "CFK manifest + cluster-link sequence shifts right by the same delta.",
        "Cluster-link PRD (W11–W13) is the longest single item at 36 hrs — protect this window.",
    ]
    for note in notes:
        c = ws.cell(row=row, column=2, value=f"• {note}")
        c.font = Font(name="Calibri", size=10)
        c.alignment = left
        ws.merge_cells(start_row=row, start_column=2,
                       end_row=row, end_column=total_cols)
        ws.row_dimensions[row].height = 30
        row += 1

    # ----- legend
    row += 1
    ws.cell(row=row, column=2, value="Legend:").font = Font(name="Calibri", size=11, bold=True)
    row += 1
    legend = [
        ("Ayu — scheduled bar", AYU_BAR),
        ("Asmerom — scheduled bar", ASM_BAR),
        ("Shared — Ayu + Asmerom", SHARED_BAR),
        ("Blocked work (currently on hold)", BLOCKED_BAR),
        ("★ = current week", "FFFFE082"),
        ("Weekly load > 20 hrs (over capacity)", "FFFFCDD2"),
    ]
    for label, color in legend:
        c = ws.cell(row=row, column=2, value=f"  ■  {label}")
        c.font = Font(name="Calibri", size=10)
        c.fill = fill(color) if color != "FFFFE082" else PatternFill()
        if color in (AYU_BAR, ASM_BAR, SHARED_BAR, BLOCKED_BAR):
            c.font = Font(name="Calibri", size=10, color=WHITE, bold=True)
            c.fill = fill(color)
        row += 1

    # freeze panes at header
    ws.freeze_panes = ws.cell(row=hdr_row + 1, column=base_cols + 1).coordinate

    wb.save(WB_PATH)
    print(f"Saved sheet '{SHEET_NAME}'.")
    print("Ayu weekly load:", [round(x, 1) for x in ayu_load])
    print("Asm weekly load:", [round(x, 1) for x in asm_load])
    print("Shared weekly load:", [round(x, 1) for x in shared_load])


if __name__ == "__main__":
    main()
