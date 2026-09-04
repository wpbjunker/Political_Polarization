# Voter Predictive Analytics

This repository contains Snowflake SQL script designed to clean, transform, and analyze voter behavior and sentiment data. It reduces a broad, 304-column source table down to a curated set of key indicators, calculates new composite metrics (like polarization and media preference), and generates aggregate views to explore the relationships between media consumption, policy preferences, and political alignment.

## Environment Configuration

The script sets up a standardized Snowflake environment and leverages object tagging for resource tracking.

*   **Role:** `TRAINING_ROLE`
*   **Warehouse:** `CAMEL_WH`
*   **Database:** `CAMEL_DB`
*   **Schemas:** 
    *   `VOTERS_CUR`: Curated data (cleaning, cutting, expanding).
    *   `VOTERS_AGG`: Aggregated data for exploration and reporting.
*   **Tags:** Applies `work_type = 'project'` to all generated tables for cost and metadata tracking.

## Data Cleaning & Curation (`VOTERS_CUR`)

The core curated table, `voter_identity_scores`, extracts only the most relevant features from the raw source (`HAYSTAQDNASCORES`). It aliases verbose column names for legibility and normalizes scores (1 = complete opposition, 100 = full alignment).

### Key Extracted Categories
*   **Media Usage:** TV news (MSNBC, FOX, CNN), podcasts, and social media.
*   **Party Affiliations & Voting:** General GOP/Democrat alignment and candidate preferences.
*   **Policy Preferences:** Support for various policies affiliated with either party platform.

### Engineered Features
The script dynamically categorizes voters into discrete buckets using SQL `CASE` statements:

*   **`media_preference`:** Categorizes voters as `legacy_media`, `new_media`, `both_media`, or `no_media` based on their engagement with TV versus podcasts/social media.
*   **`political_affiliation`:** Classifies voters as strictly `republican` or `democrat`. *(Note: Unaffiliated voters are purged from the dataset).*
*   **`view_of_opposition`:** Measures individual polarization by categorizing voters as `civil`, `misguided`, `foolish`, or `hostile` based on how secure/dangerous or informed/misinformed they view the opposing party.

## Stored Procedures

### `gen_orthodoxy_proc(DIVIDING_SCORE)`
A dynamic SQL procedure that evaluates how closely a voter's specific policy preferences align with their stated party.
*   **`party_platform_alignment`:** A continuous score calculated by summing Democratic-affiliated policy preferences and subtracting Republican-affiliated policy preferences.
*   **`party_orthodoxy`:** Categorizes the voter as `dem_orthodox`, `dem_heterodox`, `gop_orthodox`, or `gop_heterodox` based on the intersection of their alignment score and stated political affiliation.

## Data Exploration & Aggregations (`VOTERS_AGG`)

Several reporting tables in the `VOTERS_AGG` schema are generated to identify macro-trends across the electorate:

| Table Name | Description |
| :--- | :--- |
| **`max_universal_healthcare_support_by_party_media`** | Identifies the highest levels of support for Universal Healthcare segmented by political affiliation and media diet. |
| **`min_universal_healthcare_support_by_party_media`** | Identifies the lowest levels of UHC support across the same segments. |
| **`overton_window_by_party`** | Calculates the average platform alignment score for each party orthodoxy tier to measure the breadth of acceptable policy within each party. |
| **`count_by_party_media_viewopp`** | A foundational aggregate table providing raw voter counts grouped by party, media preference, and polarization level. |
| **`party_polarization`** | Calculates the proportional distribution of polarization levels (`civil` vs `hostile`) within the Democratic and Republican parties. |
| **`media_polarization`** | Calculates the proportional distribution of polarization levels grouped entirely by the voter's media consumption habits. |
