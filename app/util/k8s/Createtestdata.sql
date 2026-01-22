CREATE OR REPLACE FUNCTION createtestdata()
RETURNS boolean
LANGUAGE 'plpgsql'
COST 100
VOLATILE 
AS $BODY$
DECLARE
    proj RECORD;
    ruleId INTEGER;
    emailtemplateid INTEGER;
    otherTemplates RECORD;
    markdownTemplateId INTEGER;
    pdfTemplateId INTEGER;
    jsonTemplateId INTEGER;
    copyProjectId CONSTANT INTEGER := 110000;
    rule_count CONSTANT INTEGER := 100; -- Define how many rules to create per project
BEGIN

    RAISE NOTICE 'Inserting rules';

    FOR proj IN
        SELECT p.id AS project_id FROM project p
        WHERE p.id != copyProjectId
        ORDER BY p.id
    LOOP
        RAISE NOTICE 'Inserting LOCAL templates data for project %', proj.project_id;

        INSERT INTO "AO_299380_ARN_TEMPLATES" 
            ("NAME", "SUBJECT", "PROJECT_ID", 
             "ARN_BRANDING", "BODY", "CREATED", "CREATED_BY", 
             "IS_DELETED", "LEVEL_NEW", "MODIFIED", "MODIFIED_BY",  
             "TYPE", "USE_IF_JQL")
        SELECT 'LOCAL ' || templates."NAME" AS "NAME", templates."SUBJECT", proj.project_id, 
               templates."ARN_BRANDING", templates."BODY", templates."CREATED", templates."CREATED_BY", 
               templates."IS_DELETED", 1, templates."MODIFIED", templates."MODIFIED_BY",  
               templates."TYPE", templates."USE_IF_JQL"
        FROM "AO_299380_ARN_TEMPLATES" AS templates WHERE templates."PROJECT_ID" = copyProjectId;

        -- Fetch email template ID
        SELECT "ID" FROM "AO_299380_ARN_TEMPLATES" 
        WHERE "PROJECT_ID" = proj.project_id AND "TYPE" = 1 
        ORDER BY RANDOM() LIMIT 1
        INTO emailtemplateid;

        RAISE NOTICE 'Template ID is %', emailtemplateid;

        -- Fetch other templates
        SELECT "ID", "TYPE" FROM "AO_299380_ARN_TEMPLATES" 
        WHERE "PROJECT_ID" = proj.project_id AND "TYPE" IN (2, 4, 5)
        ORDER BY RANDOM() LIMIT 1
        INTO otherTemplates;

        RAISE NOTICE 'Other Templates %', otherTemplates;

        pdfTemplateId = NULL;
        markdownTemplateId = NULL;
        jsonTemplateId = NULL;

        IF otherTemplates."TYPE" = 2 THEN
            pdfTemplateId = otherTemplates."ID";
        ELSIF otherTemplates."TYPE" = 4 THEN
            markdownTemplateId = otherTemplates."ID";
        ELSIF otherTemplates."TYPE" = 5 THEN
            jsonTemplateId = otherTemplates."ID";
        END IF;

        RAISE NOTICE 'PDF Template ID: %, Markdown Template ID: %, JSON Template ID: %', 
                     pdfTemplateId, markdownTemplateId, jsonTemplateId;

        -- Insert rules and actions based on the rule count
        FOR i IN 1..rule_count LOOP
            RAISE NOTICE 'Inserting rule % for project %', i, proj.project_id;

            INSERT INTO "AO_299380_ARN_RULES"(
                "BEFORE_NOF_DAYS", "CREATED", "CREATED_BY", "CRON_EXPRESSION", "IS_ACTIVE", 
                "IS_DELETED", "MODIFIED", "MODIFIED_BY", "NAME", 
                "PROJECT_ID", "SCHEDULE_TIME", "TRIGGER_TYPE", "VERSION_PATTERN", "RUN_RULE_AS")
            VALUES (null, now(), 'admin', null, true, 
                    false, now(), 'admin', 'Rule ' || i || ' for project ' || proj.project_id, 
                    proj.project_id, null, 2, null, 'APP_USER') 
            RETURNING "ID" INTO ruleId;

            RAISE NOTICE 'Inserting email action for Rule ID just created is %', ruleId;

            INSERT INTO "AO_299380_ARN_RULE_ACTIONS"(
                "ACTION_TYPE", "CONFLUENCE_INSTANCE_ID", "CREATED", "CREATED_BY", "EMAIL_FROM", 
                "EXTERNAL_USERS", "IS_DELETED", "JIRA_GROUPS", "JIRA_USERS", "JSON_TEMPLATE_ID", "MARKDOWN_TEMPLATE_ID",
                "MODIFIED", "MODIFIED_BY", "NAME", 
                "PAGE_LABEL", "PARENT_ID", "PDF_TEMPLATE_ID", "PORTAL_ID", "POST_END_POINT", "POST_PASSWORD", 
                "POST_TEMPLATE_TYPE", "POST_TYPE", "POST_USER_NAME", "REPLY_TO", "RULE_ID", 
                "SEND_EMAIL_AS_BCC", "SEQUENCE_NUMBER", "SPACE_KEY", "TEMPLATE_ID", "TEMPLATE_TYPE_ID")
            VALUES (1, NULL, NOW(), 'admin', 'sourya@amoeboids.com', 
                    '', false, 'arn-users', 'admin', jsonTemplateId, markdownTemplateId, 
                    now(), 'admin', 'Email action for rule ' || i || ' for project ' || proj.project_id, 
                    NULL, 0, pdfTemplateId, 0, NULL, NULL, 
                    NULL, 'page', NULL, 'sourya@amoeboids.com', ruleId, 
                    false, i, NULL, emailtemplateid, 1);
        END LOOP;
    END LOOP;

    RETURN true;
END;
$BODY$;


select createtestdata();

