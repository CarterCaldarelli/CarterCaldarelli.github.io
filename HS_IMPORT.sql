WITH  
       --Get today's date
       CUR_DATE AS (SELECT TRUNC(SYSDATE) AS TODAY 
                      FROM DUAL)
       --Identify term based on today's date
     , CUR_TERM AS (SELECT CASE WHEN (SELECT TODAY FROM CUR_DATE) BETWEEN TO_DATE('06-APR-20', 'DD-MON-YY') AND TO_DATE('05-JUL-20', 'DD-MON-YY')
                                THEN 202030
                                WHEN (SELECT TODAY FROM CUR_DATE) BETWEEN TO_DATE('06-JUL-20', 'DD-MON-YY') AND TO_DATE('20-SEP-20', 'DD-MON-YY')
                                THEN 202060
                                WHEN (SELECT TODAY FROM CUR_DATE) BETWEEN TO_DATE('21-SEP-20', 'DD-MON-YY') AND TO_DATE('10-JAN-21', 'DD-MON-YY')
                                THEN 202090
                                WHEN (SELECT TODAY FROM CUR_DATE) BETWEEN TO_DATE('11-JAN-21', 'DD-MON-YY') AND TO_DATE('04-APR-21', 'DD-MON-YY')
                                THEN 202110
                            END CURRENT_TERM 
                      FROM DUAL)
     --Define term start dates
     , TERM_STARTS AS (SELECT    TO_DATE('05-APR-21', 'DD-MON-YY') AS SPRING_START
                               , TO_DATE('06-JUL-20', 'DD-MON-YY') AS SUMMER_START
                               , TO_DATE('21-SEP-20', 'DD-MON-YY') AS FALL_START
                               , TO_DATE('11-JAN-21', 'DD-MON-YY') AS WINTER_START
                         FROM  DUAL)
     --Dynamically generate termcode for next term
     , NEXT_TERM AS (SELECT CASE WHEN SUBSTR((SELECT CURRENT_TERM FROM CUR_TERM),5,6) IN (90,10)
                                  THEN (SELECT CURRENT_TERM FROM CUR_TERM) + 20
                             ELSE (SELECT CURRENT_TERM FROM CUR_TERM) + 30
                      END SUB_TERM 
                      FROM DUAL)                   
     --Identifies the upcoming term start date based on current term
     , NEXT_IMPORT_TERM AS (SELECT CASE WHEN SUBSTR((SELECT CURRENT_TERM FROM CUR_TERM),5,2) = 10 
                                   THEN (SELECT SPRING_START FROM TERM_STARTS)
                                   WHEN SUBSTR((SELECT CURRENT_TERM FROM CUR_TERM),5,2) = 30 
                                   THEN (SELECT SUMMER_START FROM TERM_STARTS)
                                   WHEN SUBSTR((SELECT CURRENT_TERM FROM CUR_TERM),5,2) = 60 
                                   THEN (SELECT FALL_START FROM TERM_STARTS)
                                   WHEN SUBSTR((SELECT CURRENT_TERM FROM CUR_TERM),5,2) = 90 
                                   THEN (SELECT WINTER_START FROM TERM_STARTS)
                               END IMP_TERM
                         FROM  DUAL)
     --Sets the termcode for the main query depending on how many days today is away from identified term start date.  If date
     --is within 1 week prior to term start date, set termcode to next term, otherwise set termcode to current term.                                                    
     , SET_TERM AS (SELECT CASE WHEN (SELECT TODAY FROM CUR_DATE) - (SELECT IMP_TERM FROM NEXT_IMPORT_TERM) > -8
                                THEN (SELECT SUB_TERM FROM NEXT_TERM)
                                ELSE (SELECT CURRENT_TERM FROM CUR_TERM)
                            END DYN_TERM
                      FROM DUAL)
     --Create lookup table for all enrolled undergraduate students with partnership type or HP3 cohort code, and total credits earned.  Used to identify class.                  
     , UG_CLASS_LKUP AS (SELECT DISTINCT    ENR_PIDM AS TYPE_PIDM
                                          , NVL(HP3_COHORT, ENR_PARTNERSHIP_TYPE) AS COHORT
                                          , ENR_PRIMARY_CAMPUS_CODE AS CAMPUS 
                                          , ENR_PROGRAM_CODE AS PROGRAM  
                                          , LGPA_LEVEL_CODE AS CLASS_LEVEL
                                          , (NVL(LGPA_NLU_EARNED,0) + NVL(LGPA_TRANSFER_EARNED,0)) AS CREDITS_EARNED
                                    FROM    T_BI_ENROLLMENT
                                          , T_BI_HP3
                                          , BAN_GPA_LEVEL
                                   WHERE    ENR_PIDM = HP3_PIDM (+)
                                     AND    ENR_PIDM = LGPA_PIDM (+)
                                     AND    ENR_TERM_CODE IN (SELECT DYN_TERM FROM SET_TERM)
                                     AND    ENR_LEVEL_CODE = 'UG'
                                     AND    LGPA_LEVEL_CODE = 'UG')
     --GPA lookup tables by level
     , GR_GPA_LKUP AS (SELECT    LGPA_PIDM AS GR_PIDM 
                               , LGPA_NLU_GPA AS GR_GPA
                         FROM    BAN_GPA_LEVEL
                        WHERE    LGPA_LEVEL_CODE = 'GR')
     , UG_GPA_LKUP AS (SELECT    LGPA_PIDM AS UG_PIDM
                               , LGPA_NLU_GPA AS UG_GPA
                         FROM    BAN_GPA_LEVEL
                        WHERE    LGPA_LEVEL_CODE = 'UG')
     --Advisor email address lookup table                      
     , ADV_EMAIL_LKUP AS (SELECT DISTINCT   STU_PIDM AS ADV_PIDM
                                          , STU_EMAIL_EMPLOYEE AS ADV_EMAIL
                                     FROM   T_BI_STUDENT
                                          , BAN_CURRENT_ADVISOR
                                    WHERE   STU_PIDM = ADVR_ADVR_PIDM
                                      AND   STU_EMAIL_EMPLOYEE IS NOT NULL)               
--Select columns for import file                                    
SELECT    STU_EMAIL_NLU AS EMAIL_ADDRESS
        , REGEXP_SUBSTR(STU_EMAIL_NLU, '^([a-zA-Z0-9_\-\.]+)',1) AS USERNAME
        , REGEXP_SUBSTR(STU_EMAIL_NLU, '^([a-zA-Z0-9_\-\.]+)',1) AS AUTH_IDENTIFIER
        , STU_ID AS CARD_ID
        , STU_FIRST AS FIRST_NAME
        , STU_LAST AS LAST_NAME
        , STU_MI AS MIDDLE_NAME
        , STU_PREFERRED_FIRST_NAME AS PREFERRED_NAME
        --Identifies UG class by cohort code if Pathways or by credits if A/T or Helix. Uses degree code to identify Master's or Doctorate.
        , CASE WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP
                                  WHERE   SUBSTR(COHORT, 3, 4) IN ('1960','1990', '2010','2030'))
                                   THEN   'Freshman'
               WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP 
                                  WHERE   SUBSTR(COHORT, 3, 4) IN('1860','1890','1910','1930'))
                                   THEN   'Sophomore'
               WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP 
                                  WHERE   SUBSTR(COHORT, 3, 4) IN('1760','1790','1810','1830'))
                                   THEN   'Junior'
               WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP
                                  WHERE   SUBSTR(COHORT, 3, 4) IN('1590', '1610', '1630', '1660', '1690', '1710', '1730'))
                                   THEN   'Senior'
               WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP
                                  WHERE   COHORT IN ('Non-Partnership', 'Helix Online')
                                    AND   (CREDITS_EARNED IS NULL OR CREDITS_EARNED < 45))
                                   THEN   'Freshman'
               WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP
                                  WHERE   COHORT IN ('Non-Partnership', 'Helix Online')
                                    AND   CREDITS_EARNED BETWEEN 45 AND 89.9)
                                   THEN   'Sophomore' 
               WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP
                                  WHERE   COHORT IN ('Non-Partnership', 'Helix Online')
                                    AND   CREDITS_EARNED BETWEEN 90 AND 134.9)
                                   THEN   'Junior' 
               WHEN ENR_PIDM IN (SELECT   TYPE_PIDM
                                   FROM   UG_CLASS_LKUP
                                  WHERE   COHORT IN ('Non-Partnership', 'Helix Online')
                                    AND   CREDITS_EARNED >= 135)
                                   THEN   'Senior'
               WHEN ENR_DEGREE_CODE IN    ('MAT','MED','MS','MA','MBA','MHA','MSED','MADE','MPA','MAED') 
                                    OR    ENR_LEVEL_CODE = 'GR'
                                   THEN   'Masters'
               WHEN ENR_DEGREE_CODE IN ('EDD','EDS','PHD','DPSY','DBA')
                                   THEN   'Doctorate'                     
                                   ELSE   ''
          END SCHOOL_YEAR_NAME
        , CASE WHEN ENR_DEGREE_CODE IN ('MAT','MED','MS','MA','MBA','MHA','MSED','MADE','MPA','MAED')
               THEN 'Masters'
               WHEN ENR_DEGREE_CODE IN ('BA','BS') 
               THEN 'Bachelors'
               WHEN ENR_DEGREE_CODE IN ('EDD','EDS','PHD','DPSY','DBA')
               THEN 'Doctorate'
               WHEN ENR_DEGREE_CODE IN ('AP','AS')
               THEN 'Associates'
               WHEN ENR_DEGREE_CODE IN ('CAS','CRTE','CRTB','CRTG')
               THEN 'Certificate'
               WHEN ENR_DEGREE_CODE IN ('NONE','0000UG','000000')
               THEN 'Non-Degree Seeking'
          END "PRIMARY_EDUCATION:EDUCATION_LEVEL_NAME"   
        --Lookup GPA based on level code
        , CASE WHEN ENR_LEVEL_CODE = 'GR'
               THEN (SELECT GR_GPA
                       FROM GR_GPA_LKUP
                      WHERE ENR_PIDM = GR_PIDM)
               WHEN ENR_LEVEL_CODE = 'UG'
               THEN (SELECT UG_GPA
                       FROM UG_GPA_LKUP
                      WHERE ENR_PIDM = UG_PIDM)
          END "PRIMARY_EDUCATION:CUMULATIVE_GPA"
        , ENR_MAJOR_DESC AS "PRIMARY_EDUCATION:MAJOR_NAMES"
        , ENR_MAJOR_DESC AS "PRIMARY_EDUCATION:PRIMARY_MAJOR_NAME"
        , ENR_MINOR_DESC AS "PRIMARY_EDUCATION:MINOR_NAMES"
        , ENR_COLLEGE_DESC||' at National Louis University' AS "PRIMARY_EDUCATION:COLLEGE_NAME"
        , 'TRUE' AS "PRIMARY_EDUCATION:CURRENTLY_ATTENDING"
        , CASE WHEN ENR_PRIMARY_CAMPUS_DESC NOT IN ('Beloit','Chicago', 'Elgin', 'Kendall Campus', 'Lisle', 'North Shore','On-line','Professional Devl. Ctr.', 'Tampa','Wheeling')
               THEN ''
               ELSE ENR_PRIMARY_CAMPUS_DESC
           END CAMPUS_NAME
        , STU_RESIDENCY_ETHNICITY AS ETHNICITY
        , CASE WHEN STU_GENDER = 'F' 
               THEN 'Female'
               WHEN STU_GENDER = 'M' 
               THEN 'Male'
               ELSE ''
          END GENDER     
        , STU_PHONE_NUMBER AS MOBILE_NUMBER
        --Assign career advisor based on campus and program if Pathways, assign Olivia if Helix, otherwise assign academic advisor
        , CASE WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP 
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH')
               THEN  'bsarkar@nl.edu'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP 
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM IN ('BA BA', 'BA AC', 'BS CIS'))
               THEN  'mvicars1@nl.edu'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP 
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM IN ('BA ECP','BA_ECED','BA ECE','BA SS/ECE','BA LAS/ECE','BA ELED','BA SS/ELED','BA LAS/ELED',
                                        'BA SPE','BA SS/SPE','BA LAS/SPE','BA HMS','BA HMSPSYCH','BA PSYCH'))
               THEN  'dwilliams44@nl.edu'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP 
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM IN ('BA CJ'))
               THEN  'jmcgill3@nl.edu'
               WHEN  ENR_PARTNERSHIP_TYPE = 'Helix Online'
               THEN  'osmith6@nl.edu'
               WHEN  ENR_COLLEGE_CODE = 'KC'
                AND  ENR_PROGRAM_CODE IN ('AAS_CULA', 'BA_HOSM', 'BA_CULA','AAS_CULAACL', 'AAS_BAPA', 'CRTU PC', 'CRTU BAPA', 'BA_CULA_PD', 'BA_HOSM_PD')
               THEN  'dbosco1@nl.edu'
               ELSE  (SELECT    ADV_EMAIL
                        FROM    ADV_EMAIL_LKUP
                              , BAN_CURRENT_ADVISOR
                       WHERE    ENR_PIDM = ADVR_STU_PIDM
                         AND    ADVR_ADVR_PIDM = ADV_PIDM)
          END ASSIGNED_TO_EMAIL_ADDRESS
        --Assign system level label used to control appointment flow in Handshake
        , CASE WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA BA')
               THEN  'ft/dt;ba_ba_wh'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA AC')
               THEN  'ft/dt;ba_ac_wh'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA CJ')
               THEN  'ft/dt;ba_cj_wh'  
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA HMS')
               THEN  'ft/dt;ba_hms_wh' 
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA PSYCH')
               THEN  'ft/dt;ba_psych_wh' 
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BS CIS')
               THEN  'ft/dt;bs_cis_wh' 
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA ECE')
               THEN  'ft/dt;ba_ece_wh'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA ECP')
               THEN  'ft/dt;ba_ecp_wh'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM = 'BA ELED')
               THEN  'ft/dt;ba_eled_wh'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'WH'
                                     AND PROGRAM IN ('BA SPE', 'BA SS/SPE', 'BA SS/ELED'))
               THEN  'ft/dt;ba_spe_wh'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA BA')
               THEN  'ft/dt;ba_ba_ch'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA AC')
               THEN  'ft/dt;ba_ac_ch'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA CJ')
               THEN  'ft/dt;ba_cj_ch'  
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA HMS')
               THEN  'ft/dt;ba_hms_ch' 
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA PSYCH')
               THEN  'ft/dt;ba_psych_ch' 
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BS CIS')
               THEN  'ft/dt;bs_cis_ch' 
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA ECE')
               THEN  'ft/dt;ba_ece_ch'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA ECP')
               THEN  'ft/dt;ba_ecp_ch'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM = 'BA ELED')
               THEN  'ft/dt;ba_eled_ch'
               WHEN  ENR_PIDM IN (SELECT TYPE_PIDM
                                    FROM UG_CLASS_LKUP
                                   WHERE COHORT NOT IN ('Non-Partnership', 'Helix Online')
                                     AND CAMPUS = 'CH'
                                     AND PROGRAM IN ('BA SPE', 'BA SS/SPE', 'BA SS/ELED'))
               THEN  'ft/dt;ba_spe_ch'
               WHEN  ENR_PARTNERSHIP_TYPE = 'Helix Online'
               THEN  'helix'
               WHEN  ENR_LEVEL_CODE = 'UG'
                AND  ENR_PARTNERSHIP_TYPE = 'Non-Partnership'
                AND  ENR_PROGRAM_CODE NOT IN ('AAS_CULA', 'BA_HOSM', 'BA_CULA', 'AAS_BAPA', 'CRTU PC', 'CRTU BAPA', 'BA_CULA_PD', 'BA_HOSM_PD')
               THEN  'a/t'
               WHEN  ENR_COLLEGE_CODE = 'KC'
               THEN  'kendall'
               WHEN  ENR_LEVEL_CODE = 'GR'
                AND  ENR_PARTNERSHIP_TYPE NOT IN ('Helix Online')
               THEN  'grad_stu'
          END SYSTEM_LABEL_NAMES
  FROM    T_BI_STUDENT
        , T_BI_ENROLLMENT
 WHERE    STU_PIDM = ENR_PIDM
   AND    ENR_TERM_STATUS_CODE = 'REG'
   AND    ENR_TERM_CODE IN (SELECT DYN_TERM FROM SET_TERM)