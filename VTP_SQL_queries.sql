/* =====================================================================================
   YOUTH VOCATIONAL TRAINING PROGRAM - IMPACT EVALUATION
 
   Design   : Baseline (Feb 2025) and endline (Feb 2026) survey of 200 youth.
              Treatment = 120 youth who completed training; Comparison = 80 waitlisted applicants.
   Method   : Difference-in-differences (DiD) on the panel of youth interviewed in both rounds.
              Impact = (treatment endline - treatment baseline) - (comparison endline - comparison baseline)
   Input    : 03_vtp_clean_data.csv (one row per respondent per round, output of the Excel cleaning template)
   Note     : Data is synthetic, generated for demonstration.
   ===================================================================================== */

/* -------------------------------------------------------------------------------------
   Q1. SAMPLE SIZE AND ATTRITION
   How many youth were interviewed in each round, and how many did we lose at endline?
   ------------------------------------------------------------------------------------- */
SELECT
  study_group,
  COUNTIF(survey_round = 'baseline')                                         AS n_baseline,
  COUNTIF(survey_round = 'endline')                                          AS n_endline,
  COUNTIF(survey_round = 'baseline') - COUNTIF(survey_round = 'endline')     AS n_lost,
  ROUND(SAFE_DIVIDE(COUNTIF(survey_round = 'endline'),
                    COUNTIF(survey_round = 'baseline')), 3)                  AS retention_rate
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
GROUP BY study_group
ORDER BY study_group DESC;


/* -------------------------------------------------------------------------------------
   Q2. BASELINE BALANCE CHECK
   Were the two groups similar before the training? Large gaps weaken the comparison.
   ------------------------------------------------------------------------------------- */
WITH b AS (
  SELECT * FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE survey_round = 'baseline'
)
SELECT 'Female (share)'               AS characteristic,
       ROUND(AVG(CASE WHEN study_group = 'treatment'  THEN (CASE WHEN gender = 'female' THEN 1 ELSE 0 END) END), 3) AS treatment,
       ROUND(AVG(CASE WHEN study_group = 'comparison' THEN (CASE WHEN gender = 'female' THEN 1 ELSE 0 END) END), 3) AS comparison
FROM b
UNION ALL
SELECT 'Age (mean years)',
       ROUND(AVG(CASE WHEN study_group = 'treatment'  THEN age END), 2),
       ROUND(AVG(CASE WHEN study_group = 'comparison' THEN age END), 2)
FROM b
UNION ALL
SELECT 'Vocational high school graduate (share)',
       ROUND(AVG(CASE WHEN study_group = 'treatment'  THEN (CASE WHEN education = 'vocational_hs' THEN 1 ELSE 0 END) END), 3),
       ROUND(AVG(CASE WHEN study_group = 'comparison' THEN (CASE WHEN education = 'vocational_hs' THEN 1 ELSE 0 END) END), 3)
FROM b
UNION ALL
SELECT 'Employed (share)',
       ROUND(AVG(CASE WHEN study_group = 'treatment'  THEN employed_flag END), 3),
       ROUND(AVG(CASE WHEN study_group = 'comparison' THEN employed_flag END), 3)
FROM b
UNION ALL
SELECT 'Life Skills Index (1-4)',
       ROUND(AVG(CASE WHEN study_group = 'treatment'  THEN ls_index END), 3),
       ROUND(AVG(CASE WHEN study_group = 'comparison' THEN ls_index END), 3)
FROM b
UNION ALL
SELECT 'Job applications, past 12 months (mean)',
       ROUND(AVG(CASE WHEN study_group = 'treatment'  THEN job_applications END), 2),
       ROUND(AVG(CASE WHEN study_group = 'comparison' THEN job_applications END), 2)
FROM b;
 

/* -------------------------------------------------------------------------------------
   Q3. KEY OUTCOMES BY GROUP AND ROUND (panel respondents only)
   ------------------------------------------------------------------------------------- */
SELECT
  study_group,
  survey_round,
  COUNT(*)                                       AS n,
  ROUND(AVG(employed_flag), 3)                   AS employment_rate,
  ROUND(AVG(formal_job_flag), 3)                 AS formal_employment_rate,
  ROUND(AVG(ls_index), 3)                        AS life_skills_index,
  ROUND(AVG(job_applications), 2)                AS avg_job_applications,
  ROUND(AVG(CASE WHEN further_learning = 'yes' THEN 1 ELSE 0 END), 3) AS further_learning_rate
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
WHERE in_panel = 1
GROUP BY study_group, survey_round
ORDER BY study_group DESC, survey_round;


/* -------------------------------------------------------------------------------------
   Q4. IMPACT ESTIMATE: DIFFERENCE-IN-DIFFERENCES WITH 95% CONFIDENCE INTERVAL
   For each panel respondent: change = endline value - baseline value.
   DiD = mean change (treatment) - mean change (comparison)
   SE  = sqrt(var_T / n_T + var_C / n_C)      (Welch two-sample on change scores)
   An estimate is significant at 5% when |t| > 1.96 (the CI does not cross zero).
   ------------------------------------------------------------------------------------- */
WITH panel AS (
  SELECT
    respondent_id,
    MAX(study_group) AS study_group,
    MAX(CASE WHEN survey_round = 'endline' THEN employed_flag END)
      - MAX(CASE WHEN survey_round = 'baseline' THEN employed_flag END)    AS d_employed,
    MAX(CASE WHEN survey_round = 'endline' THEN formal_job_flag END)
      - MAX(CASE WHEN survey_round = 'baseline' THEN formal_job_flag END)  AS d_formal,
    MAX(CASE WHEN survey_round = 'endline' THEN ls_index END)
      - MAX(CASE WHEN survey_round = 'baseline' THEN ls_index END)         AS d_ls_index,
    MAX(CASE WHEN survey_round = 'endline' THEN job_applications END)
      - MAX(CASE WHEN survey_round = 'baseline' THEN job_applications END) AS d_applications
  FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
  WHERE in_panel = 1
  GROUP BY respondent_id
),
changes_long AS (
  SELECT study_group, 'Employment rate (pp)'          AS indicator, 1 AS sort_order, d_employed     AS d FROM panel UNION ALL
  SELECT study_group, 'Formal employment rate (pp)',                2,               d_formal            FROM panel UNION ALL
  SELECT study_group, 'Life Skills Index (points, 1-4)',            3,               d_ls_index          FROM panel UNION ALL
  SELECT study_group, 'Job applications (count)',                   4,               d_applications      FROM panel
),
stats AS (
  SELECT
    indicator, sort_order,
    AVG(CASE WHEN study_group = 'treatment'  THEN d END)             AS mean_change_t,
    AVG(CASE WHEN study_group = 'comparison' THEN d END)             AS mean_change_c,
    VAR_SAMP(CASE WHEN study_group = 'treatment'  THEN d END)        AS var_t,
    VAR_SAMP(CASE WHEN study_group = 'comparison' THEN d END)        AS var_c,
    COUNT(CASE WHEN study_group = 'treatment'  THEN d END)           AS n_t,
    COUNT(CASE WHEN study_group = 'comparison' THEN d END)           AS n_c
  FROM changes_long
  GROUP BY indicator, sort_order
)
SELECT
  indicator,
  n_t, n_c,
  ROUND(mean_change_t, 3)                                      AS change_treatment,
  ROUND(mean_change_c, 3)                                      AS change_comparison,
  ROUND(mean_change_t - mean_change_c, 3)                      AS did_impact,
  ROUND(SQRT(var_t / n_t + var_c / n_c), 3)                    AS std_error,
  ROUND((mean_change_t - mean_change_c) - 1.96 * SQRT(var_t / n_t + var_c / n_c), 3) AS ci95_low,
  ROUND((mean_change_t - mean_change_c) + 1.96 * SQRT(var_t / n_t + var_c / n_c), 3) AS ci95_high,
  ROUND(SAFE_DIVIDE(mean_change_t - mean_change_c, SQRT(var_t / n_t + var_c / n_c)), 2) AS t_stat,
  CASE WHEN ABS(SAFE_DIVIDE(mean_change_t - mean_change_c, SQRT(var_t / n_t + var_c / n_c))) > 1.96
       THEN 'Significant (5%)' ELSE 'Not significant' END     AS result
FROM stats
ORDER BY sort_order;

/* -------------------------------------------------------------------------------------
   Q5. LIFE SKILLS BY DOMAIN (DiD per domain, panel respondents)
   Straight-lined interviews already have blank scores, so AVG() skips them.
   ------------------------------------------------------------------------------------- */
WITH domains AS (
  SELECT study_group, survey_round, 'Self-management'                    AS domain, score_self_mgmt    AS score FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1 UNION ALL
  SELECT study_group, survey_round, 'Relationship skills',                          score_relationship          FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1 UNION ALL
  SELECT study_group, survey_round, 'Problem solving & critical thinking',           score_thinking              FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1 UNION ALL
  SELECT study_group, survey_round, 'Growth mindset & goals',                       score_growth                FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1
),
m AS (
  SELECT
    domain,
    AVG(CASE WHEN study_group = 'treatment'  AND survey_round = 'baseline' THEN score END) AS t_pre,
    AVG(CASE WHEN study_group = 'treatment'  AND survey_round = 'endline'  THEN score END) AS t_post,
    AVG(CASE WHEN study_group = 'comparison' AND survey_round = 'baseline' THEN score END) AS c_pre,
    AVG(CASE WHEN study_group = 'comparison' AND survey_round = 'endline'  THEN score END) AS c_post
  FROM domains
  GROUP BY domain
)
SELECT
  domain,
  ROUND(t_pre, 2)  AS treatment_baseline,
  ROUND(t_post, 2) AS treatment_endline,
  ROUND(c_pre, 2)  AS comparison_baseline,
  ROUND(c_post, 2) AS comparison_endline,
  ROUND((t_post - t_pre) - (c_post - c_pre), 2) AS did_impact
FROM m
ORDER BY did_impact DESC;
 

 /* -------------------------------------------------------------------------------------
   Q6. INCOME OF EMPLOYED YOUTH (IDR per month)
   Income is skewed, so report the median. One very high income was verified as genuine
   during cleaning (flag_income_verified = 1); it stays in, and the median is robust to it.
   ------------------------------------------------------------------------------------- */
SELECT
  study_group,
  survey_round,
  COUNT(monthly_income)                                    AS n_employed_with_income,
  APPROX_QUANTILES(monthly_income, 100)[OFFSET(50)]        AS median_income,
  ROUND(AVG(monthly_income), 0)                            AS mean_income,
  APPROX_QUANTILES(monthly_income, 100)[OFFSET(25)]        AS p25_income,
  APPROX_QUANTILES(monthly_income, 100)[OFFSET(75)]        AS p75_income,
  ROUND(AVG(hours_per_week), 1)                            AS avg_hours_per_week
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
WHERE employed_flag = 1
  AND in_panel = 1
GROUP BY study_group, survey_round
ORDER BY study_group DESC, survey_round;


/* -------------------------------------------------------------------------------------
   Q7. JOB SEARCH FUNNEL AT ENDLINE (applications -> interviews -> offers)
   ------------------------------------------------------------------------------------- */
SELECT
  study_group,
  COUNT(*)                                                         AS respondents,
  SUM(job_applications)                                            AS applications,
  SUM(job_interviews)                                              AS interviews,
  SUM(job_offers)                                                  AS offers,
  ROUND(SAFE_DIVIDE(SUM(job_interviews), SUM(job_applications)), 3) AS interview_rate,
  ROUND(SAFE_DIVIDE(SUM(job_offers), SUM(job_interviews)), 3)       AS offer_rate_per_interview,
  ROUND(SAFE_DIVIDE(SUM(job_offers), SUM(job_applications)), 3)     AS offers_per_application
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
WHERE survey_round = 'endline'
GROUP BY study_group
ORDER BY study_group DESC;


/* -------------------------------------------------------------------------------------
   Q8. WHO BENEFITS MOST? Employment change by gender (equity lens)
   ------------------------------------------------------------------------------------- */
WITH g AS (
  SELECT
    gender,
    AVG(CASE WHEN study_group = 'treatment'  AND survey_round = 'baseline' THEN employed_flag END) AS t_pre,
    AVG(CASE WHEN study_group = 'treatment'  AND survey_round = 'endline'  THEN employed_flag END) AS t_post,
    AVG(CASE WHEN study_group = 'comparison' AND survey_round = 'baseline' THEN employed_flag END) AS c_pre,
    AVG(CASE WHEN study_group = 'comparison' AND survey_round = 'endline'  THEN employed_flag END) AS c_post,
    COUNT(DISTINCT CASE WHEN study_group = 'treatment'  THEN respondent_id END)                    AS n_treatment,
    COUNT(DISTINCT CASE WHEN study_group = 'comparison' THEN respondent_id END)                    AS n_comparison
  FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
  WHERE in_panel = 1
  GROUP BY gender
)
SELECT
  gender, n_treatment, n_comparison,
  ROUND(t_post - t_pre, 3)                     AS treatment_change,
  ROUND(c_post - c_pre, 3)                     AS comparison_change,
  ROUND((t_post - t_pre) - (c_post - c_pre), 3) AS did_employment
FROM g
ORDER BY gender;


/* -------------------------------------------------------------------------------------
   Q9. RESULTS BY TRAINING TRACK (treatment group, panel)
   Small groups per track: read as descriptive, not as separate impact estimates.
   ------------------------------------------------------------------------------------- */
SELECT
  applied_track,
  COUNT(DISTINCT respondent_id)                                                      AS youth,
  ROUND(AVG(CASE WHEN survey_round = 'baseline' THEN employed_flag END), 3)          AS employment_baseline,
  ROUND(AVG(CASE WHEN survey_round = 'endline'  THEN employed_flag END), 3)          AS employment_endline,
  ROUND(AVG(CASE WHEN survey_round = 'endline'  THEN employed_flag END)
      - AVG(CASE WHEN survey_round = 'baseline' THEN employed_flag END), 3)          AS change_pp,
  ROUND(AVG(CASE WHEN survey_round = 'endline'  THEN ls_index END)
      - AVG(CASE WHEN survey_round = 'baseline' THEN ls_index END), 2)               AS life_skills_change
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
WHERE study_group = 'treatment'
  AND in_panel = 1
GROUP BY applied_track
ORDER BY change_pp DESC;
 


 /* -------------------------------------------------------------------------------------
   Q10. TRAINING FEEDBACK AND NET PROMOTER SCORE (treatment, endline)
   NPS = % promoters (9-10) - % detractors (0-6), range -100 to +100
   ------------------------------------------------------------------------------------- */
SELECT
  COALESCE(applied_track, 'ALL TRACKS')                                            AS track,
  COUNT(nps_recommend)                                                             AS respondents,
  ROUND(AVG(training_satisfaction), 2)                                             AS avg_satisfaction_1to5,
  ROUND(SAFE_DIVIDE(COUNTIF(training_satisfaction >= 4), COUNT(training_satisfaction)), 3) AS share_satisfied,
  ROUND(AVG(training_relevance), 2)                                                AS avg_relevance_1to5,
  ROUND(SAFE_DIVIDE(COUNTIF(skills_applied = 'yes'), COUNT(skills_applied)), 3)    AS share_applied_skills,
  ROUND(100 * (SAFE_DIVIDE(COUNTIF(nps_category = 'Promoter'),  COUNT(nps_category))
             - SAFE_DIVIDE(COUNTIF(nps_category = 'Detractor'), COUNT(nps_category))), 1) AS nps
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
WHERE study_group = 'treatment'
  AND survey_round = 'endline'
GROUP BY ROLLUP(applied_track)
ORDER BY CASE WHEN applied_track IS NULL THEN 1 ELSE 0 END, nps DESC;
 

 /* =====================================================================================
   VIEWS FOR LOOKER STUDIO
   Connect Looker Studio to these views (Add data > BigQuery > socialimpactdataset).
   ===================================================================================== */
 
/* V1. Row-level table with readable labels - main data source for the dashboard */
CREATE OR REPLACE VIEW `social-impact-analysis-513703.socialimpactdataset.vw_dashboard` AS
SELECT
  respondent_id,
  interview_date,
  survey_round,
  CASE survey_round WHEN 'baseline' THEN '1. Baseline (Feb 2025)' ELSE '2. Endline (Feb 2026)' END AS round_label,
  study_group,
  CASE study_group WHEN 'treatment' THEN 'Trained youth' ELSE 'Comparison (waitlisted)' END   AS group_label,
  applied_track, cohort, gender, age, age_group, city, education, disability, enumerator,
  employed_flag, formal_job_flag, employment_type, contract_type, hours_per_week, monthly_income,
  job_applications, job_interviews, job_offers,
  CASE WHEN further_learning = 'yes' THEN 1 ELSE 0 END AS further_learning_flag,
  score_self_mgmt, score_relationship, score_thinking, score_growth, ls_index,
  training_satisfaction, training_relevance,
  CASE WHEN skills_applied = 'yes' THEN 1 WHEN skills_applied = 'no' THEN 0 END AS skills_applied_flag,
  nps_recommend, nps_category,
  CASE nps_category WHEN 'Promoter' THEN 1 WHEN 'Detractor' THEN -1 WHEN 'Passive' THEN 0 END AS nps_points,
  in_panel
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`;
 
/* V2. One row per panel respondent with before/after values - for change charts and DiD scorecards */
CREATE OR REPLACE VIEW `social-impact-analysis-513703.socialimpactdataset.vw_respondent_change` AS
SELECT
  respondent_id,
  MAX(study_group)   AS study_group,
  MAX(applied_track) AS applied_track,
  MAX(gender)        AS gender,
  MAX(CASE WHEN survey_round = 'baseline' THEN employed_flag END) AS employed_baseline,
  MAX(CASE WHEN survey_round = 'endline'  THEN employed_flag END) AS employed_endline,
  MAX(CASE WHEN survey_round = 'baseline' THEN ls_index END)      AS ls_index_baseline,
  MAX(CASE WHEN survey_round = 'endline'  THEN ls_index END)      AS ls_index_endline,
  MAX(CASE WHEN survey_round = 'endline'  THEN ls_index END)
    - MAX(CASE WHEN survey_round = 'baseline' THEN ls_index END)  AS ls_index_change,
  CASE
    WHEN MAX(CASE WHEN survey_round = 'baseline' THEN employed_flag END) = 0
     AND MAX(CASE WHEN survey_round = 'endline'  THEN employed_flag END) = 1 THEN 'Found work'
    WHEN MAX(CASE WHEN survey_round = 'baseline' THEN employed_flag END) = 1
     AND MAX(CASE WHEN survey_round = 'endline'  THEN employed_flag END) = 1 THEN 'Stayed employed'
    WHEN MAX(CASE WHEN survey_round = 'baseline' THEN employed_flag END) = 1
     AND MAX(CASE WHEN survey_round = 'endline'  THEN employed_flag END) = 0 THEN 'Lost work'
    ELSE 'Still not working'
  END AS employment_transition
FROM `social-impact-analysis-513703.socialimpactdataset.cleaned`
WHERE in_panel = 1
GROUP BY respondent_id;
 
/* V3. Life skills in long format - one row per respondent x round x domain (for domain bar charts) */
CREATE OR REPLACE VIEW `social-impact-analysis-513703.socialimpactdataset.vw_lifeskills_long` AS
SELECT respondent_id, study_group, survey_round, applied_track, gender, 'Self-management'                     AS domain, score_self_mgmt    AS score FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1 UNION ALL
SELECT respondent_id, study_group, survey_round, applied_track, gender, 'Relationship skills',                           score_relationship          FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1 UNION ALL
SELECT respondent_id, study_group, survey_round, applied_track, gender, 'Problem solving & critical thinking',            score_thinking              FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1 UNION ALL
SELECT respondent_id, study_group, survey_round, applied_track, gender, 'Growth mindset & goals',                        score_growth                FROM `social-impact-analysis-513703.socialimpactdataset.cleaned` WHERE in_panel = 1;
 

