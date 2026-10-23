# Power BI: portable export and working-repository report

## Recommended for visitors: download the complete project

From the analyzer choose **Import data → Run analysis → Download Power BI project ZIP**. The package uses the current session's dataset, even if it has not been saved in the repository.

1. Extract the entire ZIP into a new local folder.
2. Open `SubscriptionAnalytics.pbip` in Power BI Desktop.
3. Click **Home → Refresh** once to load the embedded scenario.
4. Explore Overview and Retention; optionally save a local PBIX copy.

No source-repository download, `DataFolder` change, network source, sign-in for publication, Docker, R or BAT/CMD launcher is needed to use that exported Desktop project. Power BI Desktop itself is required.

The data bytes are embedded in each table's Power Query definition. CSV copies in `data/` are included for inspection, not read by the embedded model. Moving the extracted folder therefore does not change its data source. Export another package to capture another scenario.

The archive also contains `dataset-info.json`, expected headline values, `OPEN-ME.md` and a self-contained R-generated `case-study.html`.

**This is a PBIP source project, not a pre-refreshed PBIX.** It has no prebuilt model cache; the first Desktop refresh is required. Native refresh/DAX/rendering must be checked in Desktop. After a successful refresh, save a PBIX if you want a single file with the loaded report data.

The original ready-to-download presentation package is `powerbi/PowerBI-Presentation.zip`.

## Alternative: CSV-only download for an existing report

Click **Download CSVs only**, extract the CSVs to the fixed local folder used by your existing report, then refresh. Set `DataFolder` if the folder changed.

The model reads `user_metrics.csv`, `payment_facts.csv` and `cohort_retention.csv`. `monthly_metrics.csv` is an additional export. The CSV archive has no report template; use the complete project export if you want both.

## Advanced: working report in a fork/branch

The repository's `powerbi/SubscriptionAnalytics.pbip` remains CSV-linked to support ongoing development:

1. Open that PBIP.
2. In **Transform data → Edit parameters / Manage Parameters**, set `DataFolder` to the absolute path of your local `data/processed` folder.
3. Apply changes and refresh.
4. After saving a different working analysis to that folder, refresh again.

Example: `C:/Users/YourName/Documents/subscription-analyzer/data/processed`.

If the analyzer runs in Codespaces, **Save on app server** changes the remote checkout. It does not change files on your PC or commit to GitHub. For immediate local viewing download the complete project. To retain changes in your own branch, review, commit and push them manually; then pull/download them locally if you want to update the CSV-linked working report.

Keep `.pbi` caches and personal Desktop state out of version control. Source definitions and CSVs are the reviewable project inputs.

## Model and metric boundaries

The two pages are **Overview** and **Retention**. Three tables and eight DAX measures are retained from the working template.

- Users → Payments is a one-to-many relationship. User filters affect related payments.
- Cohorts is disconnected and pre-aggregated. Country/channel filters on Overview do not recalculate Retention.
- Conversion excludes incomplete signup windows from both numerator and denominator.
- Collected cash includes successful first and subsequent payments; failed attempts are excluded.
- Activity retention is not paid renewal. Retention totals remain blank rather than averaging cohort percentages.

Compare unfiltered headline values against `dataset-info.json` and the HTML case study. Check active filters before investigating apparent discrepancies.

## Scope of verification

The original native template could be opened by the project owner. Export tests decode the embedded CSV bytes, compare them with the active scenario, check model/report references and preserve measures and relationships. Native Desktop refresh and rendering of the embedded export were not executed in the Linux preparation environment. Test the presentation ZIP in Windows before presenting native Power BI screenshots.
