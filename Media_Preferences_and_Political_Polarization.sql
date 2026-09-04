/* ///////////////////////////// */
/* /// CONTEXT CONFIGURATION /// */
/* ///////////////////////////// */

USE ROLE TRAINING_ROLE;
USE WAREHOUSE CAMEL_WH;
USE DATABASE CAMEL_DB;

CREATE TAG IF NOT EXISTS work_type;

CREATE SCHEMA IF NOT EXISTS VOTERS_CUR; // For cleaning, cutting, and expanding data
USE SCHEMA VOTERS_CUR;



/* ///////////////////////////// */
/* /////// DATA CLEANING /////// */
/* ///////////////////////////// */

/* 
At 304 columns, our source table has way too many attributes. About half of these are simply mirror attributes whose values are approximately the inverse of of their mirror (e.g. HS_DEI_SUPPORT and HS_DEI_OPPOSE). 
It's much more straightforward to just pick and represent full alignment as 100, complete opposition as 1. Column labels have been renamed to communicate this. The're also less verbose now, which should improve legibility.
*/
CREATE OR REPLACE TABLE voter_identity_scores AS
    SELECT 
        // primary key
        LALVOTERID AS voter_id,
        
        // media usage patterns
        HS_TV_MOST_TRUSTED_NEWS_MSNBC AS media_tv_msnbc,
        HS_TV_MOST_TRUSTED_NEWS_FOX AS media_tv_fox,
        HS_TV_MOST_TRUSTED_NEWS_CNN AS media_tv_cnn,
        HS_TV_VIEWER_NOT_VIEWER AS media_tv_none,
        HS_PODCAST_LISTENER_YES AS media_podcast,
        HS_SOCIAL_MEDIA_USER AS media_social_media,
        
        // party affiliations, voting patterns
        HS_IDEOLOGY_OVERALL_PARTY_GOP AS team_gop,
        HS_IDEOLOGY_OVERALL_PARTY_DEM AS team_dem,
        HS_TRUMP_VS_HARRIS_FAVOR_TRUMP AS trump_voter,
        HS_TRUMP_VS_HARRIS_FAVOR_HARRIS AS harris_voter,
        
        // ideology
        HS_IDEOLOGY_SOCIAL_LIBERAL AS liberalism_social,
        HS_IDEOLOGY_FISCAL_LIBERAL AS liberalism_fiscal,
        HS_IDEOLOGY_GENERAL_LIBERAL AS liberalism_general,
        HS_RELIGION_IMPORTANT AS religiosity,
        HS_CLIMATE_CHANGE_BELIEVER AS environmentalism,
        HS_CAPITALISM_BELIEVE_SOUND AS capitalism,
        
        // policy preferences
        HS_DEI_SUPPORT AS dei_support,
        HS_VIOLENT_CRIME_VERY_WORRIED AS violent_crime_concern,
        HS_TRANS_ATHLETE_YES AS trans_sports_support,
        HS_TAX_CUTS_SUPPORT AS tax_cuts_support,
        HS_SCHOOL_FUNDING_MORE AS edu_funding,
        HS_PUBLIC_TRANSIT_SUPPORT AS transit_funding,
        HS_POLICE_TRUST_YES AS  police_support,
        HS_OBAMACARE_ACA_PROTECT AS aca_support,
        HS_MIN_WAGE_15_INCREASE_SUPPORT AS min_wage_15_support,
        HS_MEXICAN_WALL_SUPPORT AS mexico_wall_support,
        HS_MEDICARE_FOR_ALL_SUPPORT AS universal_healthcare_support,
        HS_MASS_DEPORATIONS_SUPPORT AS mass_deport_support,
        HS_INCOME_INEQUALITY_SERIOUS AS inequality_concern,
        HS_GREEN_NEW_DEAL_SUPPORT AS green_new_deal_support,
        HS_DEATH_PENALTY_SUPPORT AS death_penalty_support,
        HS_CHARTER_SCHOOLS_SUPPORT AS charters_support,
        HS_UNIONS_BENEFICIAL AS unions_support,
        HS_AFFORDABLE_HOUSING_GOV_HAS_ROLE AS govt_housing_plan_support,
        HS_ABORTION_PRO_CHOICE AS abortion_rights_support,
        
        // polarization
        HS_VIEW_OF_OPPOSITION_DANGEROUS AS opponent_dangerous,
        HS_VIEW_OF_OPPOSITION_MISINFORMED AS opponent_misinformed,

        // voter classification
        /*
        Add three new categorical columns:
            media_preference: classifies voter media engagement, emphasis on traditional media and new, decentralized, internet-based media like podcasts and                                    social apps
            political_affiliation: classifies voter affiliation with the Democratic and Republican parties
            view_of_opposition: classifies voter polarization to indicate whether they support inter-party debate and compromise, or they view the opposing party                                  as so extreme, and their respective ideals so different, that any attempt at collaboration is counter-productive, or even dangerous

           New Media  No New Media
          +----------+-------------+
       TV |   Both   |   Legacy    |
          +----------+-------------+
    No TV | Just New |    None     |
          +----------+-------------+
        */
    	CASE 
    		WHEN media_tv_none <= 50 AND (media_podcast <= 50 AND media_social_media <= 50) THEN 'legacy_media' // Only watches TV
            WHEN media_tv_none > 50 AND (media_podcast > 50 OR media_social_media > 50) THEN 'new_media' // Engages non-traditional media
            WHEN media_tv_none < 50 AND (media_podcast > 50 OR media_social_media > 50) THEN 'both_media' // Diverse media usage
    		ELSE 'no_media'
    	END AS media_preference,
         /*
                    For GOP     Not GOP
                +-------------+-------------+
        For Dem |     Both    | Dem-aligned |
                +-------------+-------------+
        Not Dem | GOP-aligned |  Unaligned  |
                +-------------+-------------+
        */
        CASE
            WHEN team_gop > 50 AND team_dem <= 50 THEN 'republican'
            WHEN team_gop <= 50 AND team_dem > 50 THEN 'democrat'
            WHEN team_gop > 50 AND team_dem > 50 THEN 'both_parties' // As of now, no voters fall in this category
            ELSE 'unaffiliated' // Aligned with neither Dems nor GOP, likely apolitical
        END AS political_affiliation,
        /*
        
                        Safe     Dangerous
                    +-----------+---------+
        Misinformed | Misguided | Foolish |
                    +-----------+---------+
         Deliberate |   Civil   | Hostile |
                    +-----------+---------+
        */
        CASE
            WHEN opponent_misinformed <= 50 AND opponent_dangerous <= 50 THEN 'civil'
            WHEN opponent_misinformed > 50 AND opponent_dangerous <= 50 THEN 'misguided'
            WHEN opponent_misinformed > 50 AND opponent_dangerous > 50 THEN 'foolish'
            ELSE 'hostile'
        END AS view_of_opposition     
    FROM L2HAYSTAQDNA_VOTERSPREDICTIVEANALYTICS_MODELS.VOTERS_HAYSTAQDNA.HAYSTAQDNASCORES;
    
    ALTER TABLE voter_identity_scores SET TAG work_type = 'project';

/*
We're not interested in apolitical voters, so we'll delete rows where poliitcal_affiliation = 'unaffiliated'. 
Additionally, cases where a voter displays an score aligning them with *both* the Democratic Party and the Republican Party are likely a fluke, and should be thrown out.
*/
DELETE FROM voter_identity_scores
WHERE political_affiliation = 'unaffiliated'
    OR political_affiliation = 'both_parties';

/*
It will be useful to compare policy preference with party affinity in order to track the relationship between party platform and voter behavior.
This procedure creates, as needed, columns party_platform_alignment and party_orthodoxy, then dynamically calculates their values from existing data.
*/
CREATE OR REPLACE PROCEDURE gen_orthodoxy_proc(
    /* party_platform_aligment is somewhat arbitrary; this allows the user to select the dividing score between Left and Right */
    DIVIDING_SCORE INT DEFAULT 0
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    alter_statement VARCHAR;
    update_ppa_statement VARCHAR;
    update_porthodoxy_statement VARCHAR;
    
BEGIN
    alter_statement := 'ALTER TABLE voter_identity_scores
                            ADD 
                                COLUMN IF NOT EXISTS party_platform_alignment INT,
                                COLUMN IF NOT EXISTS party_orthodoxy VARCHAR';

    EXECUTE IMMEDIATE :alter_statement;

    // Positive score leans left, negative score leans right
    update_ppa_statement := 'UPDATE voter_identity_scores
                                SET party_platform_alignment = 
                                    // Democrat policy platform
                                    (dei_support +
                                    trans_sports_support +
                                    edu_funding +
                                    transit_funding +
                                    aca_support +
                                    min_wage_15_support +
                                    green_new_deal_support +
                                    unions_support +
                                    govt_housing_plan_support +
                                    abortion_rights_support) / 10
                                    // Republican policy platform
                                    - (violent_crime_concern +
                                    tax_cuts_support +
                                    mexico_wall_support +
                                    mass_deport_support +
                                    death_penalty_support +
                                    charters_support) / 6
                                    - ' || DIVIDING_SCORE || '
                            ';

    EXECUTE IMMEDIATE :update_ppa_statement;

    update_porthodoxy_statement := 
        'UPDATE voter_identity_scores
            SET party_orthodoxy = 
                CASE
                    WHEN political_affiliation = ''republican'' AND party_platform_alignment < 0 THEN ''gop_orthodox''
                    WHEN political_affiliation = ''republican'' AND party_platform_alignment >= 0 THEN ''gop_heterodox''
                    WHEN political_affiliation = ''democrat'' AND party_platform_alignment <= 0 THEN ''dem_heterodox''
                    WHEN political_affiliation = ''democrat'' AND party_platform_alignment > 0 THEN ''dem_orthodox''
                    ELSE NULL // All voters should fall into the above categories because we deleted voters with other political_affiliation values
                END
        ';

    EXECUTE IMMEDIATE :update_porthodoxy_statement;
                                                
    RETURN 'Successfully updated party_platform_alignment and party_orthodoxy values';
END;
$$;

CALL gen_orthodoxy_proc(-5);

/*
To recap the changes:
    1. Selected a subset of the original columns
    2. Aliased columns with standardized, less verbose labels
    3. Added calculated column 'media_preference'
    4. Added calculated column 'political_affiliation'
    5. Added calculated column 'view_of_opposition'
    6. Deleted rows that could obstruct analysis
    7. Scripted procedure to assign each row a 'party_orthodoxy' value
*/



/* ///////////////////////////// */
/* ////// DATA EXPLORATION ///// */
/* ///////////////////////////// */


CREATE SCHEMA IF NOT EXISTS VOTERS_AGG;
USE SCHEMA VOTERS_AGG;

/* 
Universal Healthcare is among the most prominent policies generally identified as 'socialist' or 'far-left'. 
It's has had strong salience in the Democratic Party, though no presidential candidate has incorporated it into their platform in the general election. 
This aggregation displays how support for UHC varies accross party affiliations and preferred media sources.
*/
CREATE OR REPLACE TABLE max_universal_healthcare_support_by_party_media AS
    SELECT political_affiliation, media_preference, MAX(universal_healthcare_support) AS max_uhc_support
    FROM CAMEL_DB.VOTERS_CUR.voter_identity_scores
    GROUP BY political_affiliation, media_preference
    ORDER BY political_affiliation, media_preference ASC;

ALTER TABLE max_universal_healthcare_support_by_party_media SET TAG work_type = 'project';



/*
Likewise, we can investigate how opposition to universal healthcare varies across these categories.
*/
CREATE OR REPLACE TABLE min_universal_healthcare_support_by_party_media AS
    SELECT political_affiliation, media_preference, MIN(universal_healthcare_support) AS min_uhc_support
    FROM CAMEL_DB.VOTERS_CUR.voter_identity_scores
    GROUP BY political_affiliation, media_preference
    ORDER BY political_affiliation, media_preference ASC;

ALTER TABLE min_universal_healthcare_support_by_party_media SET TAG work_type = 'project';
    

/*
Policy preferences don't always map onto political alignment. Taking the average alignment value for each party and each platform will give us insight into how wide the Overton window is for each party.
*/
CREATE OR REPLACE TABLE overton_window_by_party AS
    SELECT party_orthodoxy, AVG(party_platform_alignment) AS overton_window_limit
    FROM CAMEL_DB.VOTERS_CUR.voter_identity_scores
    GROUP BY party_orthodoxy
    ORDER BY party_orthodoxy ASC;

ALTER TABLE overton_window_by_party SET TAG work_type = 'project';


/*
Count of voters grouped by party, media preference, and view of opposition. This table can be further aggregated to get a picture of broader trends.
*/
CREATE OR REPLACE TABLE count_by_party_media_viewopp AS
    SELECT political_affiliation, media_preference, view_of_opposition, COUNT(*) AS count_voters
    FROM CAMEL_DB.VOTERS_CUR.voter_identity_scores
    GROUP BY political_affiliation, media_preference, view_of_opposition
    ORDER BY political_affiliation, media_preference, view_of_opposition ASC;

ALTER TABLE count_by_party_media_viewopp SET TAG work_type = 'project';

/*
Tracks the rate of polarization (non-polarized/civil to polarized/hostile) within each party.
*/
CREATE OR REPLACE TABLE party_polarization AS
    WITH
        numerators AS (
            SELECT political_affiliation, view_of_opposition, sum(count_voters) AS numerator_count
            FROM count_by_party_media_viewopp
            GROUP BY political_affiliation, view_of_opposition
        ),
        denominators AS (
            SELECT political_affiliation, sum(count_voters) AS denominator_count
            FROM count_by_party_media_viewopp
            GROUP BY political_affiliation
        )
    // Join the two to get a ratio
    SELECT 
        den.political_affiliation, 
        num.view_of_opposition, 
        ROUND((num.numerator_count / den.denominator_count), 3) AS proportion_of_party_total
    FROM numerators AS num
    INNER JOIN denominators AS den
        ON num.political_affiliation = den.political_affiliation
    ORDER BY den.political_affiliation, proportion_of_party_total DESC;

ALTER TABLE party_polarization SET TAG work_type = 'project';


/*
Tracks the rate of polarization (non-polarized/civil to polarized/hostile) within each type of preferred media (new, legacy, both, none).
*/
CREATE OR REPLACE TABLE media_polarization AS
    WITH
        numerators AS (
            SELECT media_preference, view_of_opposition, sum(count_voters) AS numerator_count
            FROM count_by_party_media_viewopp
            GROUP BY media_preference, view_of_opposition
        ),
        denominators AS (
            SELECT media_preference, sum(count_voters) AS denominator_count
            FROM count_by_party_media_viewopp
            GROUP BY media_preference
        )
    // Join the two to get a ratio
    SELECT den.media_preference,
           num.view_of_opposition,
           ROUND((num.numerator_count / den.denominator_count), 3) AS proportion_of_media_total
    FROM numerators AS num
    INNER JOIN denominators AS den
        ON num.media_preference = den.media_preference
    ORDER BY den.media_preference, proportion_of_media_total DESC;

ALTER TABLE media_polarization SET TAG work_type = 'project';


