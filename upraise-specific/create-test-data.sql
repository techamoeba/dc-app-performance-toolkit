-- function for creating test data for UpRaise PEOPLE server
CREATE OR REPLACE FUNCTION generateData(importUsers boolean, teams int, companyObj int, teamObjTeams int,
 teamObjPerTeam int, indObjUsers int, indObjPerUser int, feedbackUsers int, feedbackPerUser int,
 baseUrl text, templates int, distributionPerTemplate int, usersPerDistribution int, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		projectKeys varchar(255)[];
		projectIds numeric[];
		maxissues numeric[];
		projRec record;
		maxIssueNum int;
	BEGIN
		--PERFORM importUsers(importUsers, prefix);
		PERFORM createTeams(teams, prefix);
		projectKeys := '{}';
		projectIds := '{}';
		maxissues := '{}';
		FOR projRec IN SELECT p."id", p."pkey", MAX(i."issuenum") AS maxissues FROM "jiraissue" i
			JOIN "project" p ON i."project" = p."id"
			GROUP BY p."id", p."pkey"
		LOOP
			maxIssueNum := projRec."maxissues";
			IF (maxIssueNum IS NOT NULL) AND (maxIssueNum > 0) THEN
				projectKeys := array_append(projectKeys, projRec."pkey");
				projectIds := array_append(projectIds, projRec."id");
				maxissues := array_append(maxissues, projRec."maxissues");
			END IF;
		END LOOP;
		 PERFORM createObjectives(companyObj, teamObjTeams, teamObjPerTeam, indObjUsers, indObjPerUser, 
			projectKeys, projectIds, maxissues, baseUrl, prefix);
		 PERFORM createFeedbacks(feedbackUsers, feedbackPerUser, projectKeys, projectIds, maxissues, prefix);
		 PERFORM createFormTemplates(templates, prefix, distributionPerTemplate, usersPerDistribution);

	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION importUsers(importUsers boolean, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		jiraUser RECORD;
		role RECORD;
		status int;
		statusStr varchar(10);
		userId int;
		historyJson text;
		hisRevId int;
	BEGIN
		IF importUsers THEN 
			-- select default role to assign to newly added users
			EXECUTE 
				'SELECT "ID" AS id, "NAME" AS name, "LABEL" AS label FROM "'||prefix||'UP_ROLES" 
					WHERE "IS_DEFAULT" = true LIMIT 1' 
			INTO role ;
			-- select jira user details
			FOR jiraUser IN 
				SELECT au."user_key", cu."user_name", cu."display_name", cu."active" FROM "cwd_user" cu 
				INNER JOIN "app_user" au ON cu."lower_user_name" = au."lower_user_name" ORDER BY au."id" 
			LOOP
				IF NOT checkUserExists(jiraUser.user_key, prefix) THEN
					status := 0;
					statusStr := 'Active';
					IF jiraUser.active = 0 THEN 
						status := 1; 
						statusStr := 'Inactive';
					END IF;
					EXECUTE 
						'INSERT INTO "'||prefix||'UP_USERS" ("KEY", "USERNAME", "DISPLAY_NAME", "STATUS", 
							"TIME_ZONE", "CREATED", "CREATED_BY", "MODIFIED", "MODIFIED_BY") 
						VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)' 
					USING jiraUser.user_key, jiraUser.user_name, jiraUser.display_name, status, 
						'Asia/Kolkata', now(), 'System', now(), 'System';
					-- select newly created users id
					EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_USERS_ID_seq"'')' INTO userId;
					EXECUTE 
						'INSERT INTO "'||prefix||'UP_USER_ROLES" ("USER_ID", "ROLE_ID") VALUES ($1, $2)'
					USING userId, role.id;
					-- create user history
					historyJson := '{"value":[{"field":"status","new":"'||statusStr||'"}';
					historyJson := historyJson || ',{"field":"role","new":[{"id":'||role.id||',"name":"'||role.name||'","label":"'||role.label||'"}]}]}';
					hisRevId := createHistoryRevision(userId, prefix);
					EXECUTE
						'INSERT INTO "'||prefix||'UP_USERS_HISTORY" ("USER_ID", "HISTORY_REVISION_ID", 
							"ACTION", "VALUE") VALUES ($1, $2, $3, $4)'
					USING userId, hisRevId, 'C', historyJson;
				END IF;
			END LOOP;
		END IF;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION checkUserExists(userKey varchar(255), prefix varchar(255)) RETURNS boolean AS $$
	DECLARE
		uCount int;
	BEGIN
		EXECUTE 
			'SELECT COUNT(*) FROM "'||prefix||'UP_USERS" WHERE "KEY" = $1'
		USING userKey INTO uCount;
		RETURN uCount > 0;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createHistoryRevision(userId int, prefix varchar(255)) RETURNS int AS $$
	DECLARE
		id int;
	BEGIN
		EXECUTE
			'INSERT INTO "'||prefix||'UP_HISTORY_REV" ("CREATED", "CREATED_BY") VALUES ($1, $2)'
		USING now(), userId;
		EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_HISTORY_REV_ID_seq"'')' INTO id;
		RETURN id;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createTeams(teams int, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		startAt int;
		maxResults int;
		uCount int;
		userId int;
		teamId int;
	BEGIN
		IF teams > 0 THEN 
			EXECUTE 'SELECT COUNT(*) FROM "'||prefix||'UP_USERS" WHERE "STATUS" = 0' INTO uCount ;
			FOR i IN 1..teams LOOP
				EXECUTE
					'INSERT INTO "'||prefix||'UP_TEAMS" ("NAME", "DELETED", "CREATED", "CREATED_BY", 
					"MODIFIED", "MODIFIED_BY") VALUES ($1, $2, $3, $4, $5, $6)'
				USING 'Test Team - '||i, false, now(), 'System', now(), 'System';
				EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_TEAMS_ID_seq"'')' INTO teamId;
				-- add randomly max 10 team members
				SELECT FLOOR(random() * (10-1 + 1) + 1)::int INTO maxResults;
				SELECT FLOOR(random() * ((uCount-1)-0 + 1) + 0)::int INTO startAt;
				FOR userId IN 
					EXECUTE 
						'SELECT "ID" FROM "'||prefix||'UP_USERS" WHERE "STATUS" = $1 OFFSET $2 LIMIT $3'
					USING 0, startAt, maxResults
				LOOP
					EXECUTE
						'INSERT INTO "'||prefix||'UP_USER_TEAMS" ("USER_ID", "TEAM_ID") VALUES ($1, $2)'
					USING userId, teamId;
				END LOOP;
			END LOOP;
		END IF;
	END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION createObjectives(companyObj int, teamObjTeams int, teamObjPerTeam int,
	indObjUsers int, indObjPerUser int, projectKeys varchar(255)[], projectIds numeric[], maxissues numeric[], 
	baseUrl text, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		countVar int;
		cycle RECORD;
		labelIds int[];
		labelsCnt int;
		label int;
		owner RECORD;
		objId int;
		objTitle varchar(255);
		objDesc text;
		team RECORD;
		randomNum int;
		compObjIds int[];
		compObjTitles varchar(255)[];
		obj RECORD;
		teamObjIds int[];
		teamObjTitles varchar(255)[];
		sourceId int;
		sourceTitle varchar(255);
		objCount int;
	BEGIN
		-- select / create active obj cycle
		EXECUTE
			'SELECT COUNT(*) FROM "'||prefix||'UP_OBJ_CYCLES" WHERE "STATUS" = $1 AND "IS_DELETED" = $2'
		USING 1, false INTO countVar ;
		IF countVar = 0 THEN
			EXECUTE
				'INSERT INTO "'||prefix||'UP_OBJ_CYCLES" ("TITLE", "STATUS", "START_DATE", "END_DATE", 
					"DURATION", "IS_DELETED", "GRADING_TYPE", "GRADING_SETTINGS", "CREATED", "CREATED_BY", 
					"MODIFIED", "MODIFIED_BY") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)'
			USING 'Test data cycle', 1, CURRENT_DATE, (CURRENT_DATE + '3 month'::INTERVAL), 
				'Quarterly', false, 0, '{}', now(), 'System', now(), 'System';
		END IF;
		EXECUTE
			'SELECT "ID" AS id, "TITLE" AS title, "STATUS" AS status, "START_DATE" AS startDate, "END_DATE" AS endDate 
				FROM "'||prefix||'UP_OBJ_CYCLES" WHERE "STATUS" = $1 AND "IS_DELETED" = $2 LIMIT $3'
		USING 1, false, 1 INTO cycle;
		-- select obj labels
		labelIds := '{}';
		FOR label IN 
			EXECUTE 'SELECT "ID" FROM "'||prefix||'UP_LABELS" WHERE "TYPE" = $1' USING 2
		LOOP
			labelIds = array_append(labelIds, label);
		END LOOP;
		labelsCnt := array_length(labelIds, 1);
		-- create company objectives
		RAISE NOTICE 'creating company objectives';
		IF companyObj > 0 THEN
			compObjIds := '{}';
			compObjTitles := '{}';
			EXECUTE 
				'SELECT COUNT(*) FROM "'||prefix||'UP_USERS" WHERE "STATUS" = $1 AND "MANAGER_ID" IS NULL'
			USING 0 INTO countVar ;
			FOR i IN 1..companyObj LOOP
				-- randomly select a manager user as company objective owner
				IF (i < countVar) THEN
					EXECUTE
						'SELECT "ID" AS id, "DISPLAY_NAME" AS displayName FROM "'||prefix||'UP_USERS" 
							WHERE "STATUS" = $1 AND "MANAGER_ID" IS NULL ORDER BY "ID" LIMIT $2 OFFSET $3'
					USING 0, 1, i-1 INTO owner;
				ELSE
					EXECUTE
						'SELECT "ID" AS id, "DISPLAY_NAME" AS displayName FROM "'||prefix||'UP_USERS" 
							WHERE "STATUS" = $1 AND "MANAGER_ID" IS NULL ORDER BY "ID" LIMIT $2 OFFSET $3'
					USING 0, 1, 0 INTO owner;
				END IF;
				objTitle := 'Company objective - '||(i);
				objDesc := 'Company objective some description added '||(i);
				objId := createObj(objTitle, objDesc, 2, cycle.id, cycle.title, date(cycle.startDate), 
					date(cycle.endDate), owner.id, owner.displayName, null, null, labelsCnt, labelIds, 
					projectKeys, projectIds, maxissues, baseUrl, prefix);
				compObjIds := array_append(compObjIds, objId::int);
				compObjTitles := array_append(compObjTitles, objTitle::varchar);
				RAISE NOTICE 'created company obj = %', i;
			END LOOP;
		END IF;
		-- create team objectives
		objCount := 1;
		IF teamObjTeams > 0 AND teamObjPerTeam > 0 THEN
			-- find company obj ids to link to team objs
			IF compObjIds IS NULL OR array_length(compObjIds, 1) = 0 THEN
				compObjIds := '{}';
				compObjTitles := '{}';
				FOR obj IN 
					EXECUTE
						'SELECT "ID", "TITLE" FROM "'||prefix||'UP_OBJECTIVES" WHERE "IS_DELETED" = $1 AND 
							"OBJECTIVE_TYPE" = $2' 
					USING false, 2
				LOOP
					compObjIds := array_append(compObjIds, obj."ID"::int);
					compObjTitles := array_append(compObjTitles, obj."TITLE"::varchar);
				END LOOP;
			end if;
			FOR team IN 
				EXECUTE
					'SELECT t."ID" AS id, t."NAME" AS name, COUNT(o."TEAM_ID") AS teamObjCnt FROM 
						"'||prefix||'UP_TEAMS" t LEFT JOIN "'||prefix||'UP_OBJECTIVES" o 
						ON t."ID" = o."TEAM_ID" WHERE t."DELETED" = $1 GROUP BY t."ID", t."NAME" 
						ORDER BY teamObjCnt ASC LIMIT $2 OFFSET $3'
				USING false, teamObjTeams, 0
			LOOP
				FOR i IN 1..teamObjPerTeam LOOP
					-- get random team member for owner of team obj
					EXECUTE
						'SELECT COUNT(*) FROM "'||prefix||'UP_USER_TEAMS" WHERE "TEAM_ID" = $1'
					USING team.id INTO countVar;
					IF countVar > 0 THEN
						SELECT FLOOR(random() * ((countVar - 1)-0 + 1) + 0)::int into randomNum;
						EXECUTE
							'SELECT u."ID" AS id, u."DISPLAY_NAME" AS displayName FROM "'||prefix||'UP_USERS" u 
								JOIN "'||prefix||'UP_USER_TEAMS" t ON u."ID" = t."USER_ID"
								WHERE u."STATUS" = $1 AND t."TEAM_ID" = $2 ORDER BY u."ID" LIMIT $3 OFFSET $4'
						USING 0, team.id, 1, randomNum INTO owner;
						objTitle := 'Team objective '||i||' for '||team.name;
						objDesc := 'Team objective desc '||i||' for '||team.name;
						objId := createObj(objTitle, objDesc, 1, cycle.id, cycle.title, date(cycle.startDate), 
							date(cycle.endDate), owner.id, owner.displayName, team.id, team.name, labelsCnt, labelIds, 
							projectKeys, projectIds, maxissues, baseUrl, prefix);
						-- link team objective to company objective
						countVar := array_length(compObjIds, 1);
						IF countVar > 0 THEN
							SELECT FLOOR(random()* (countVar-1 + 1) + 1)::int into randomNum;
							sourceId := compObjIds[randomNum];
							sourceTitle := compObjTitles[randomNum];
							PERFORM createAlignment(owner.id::int, objId, objTitle, sourceId, sourceTitle, prefix);
						END IF;
						RAISE NOTICE 'created team objective = %', objCount;
						objCount := objCount +1;
					END IF;
				END LOOP;
			END LOOP;	
		END IF;
		-- create individual objectives
		objCount :=1;
		IF indObjUsers > 0 AND indObjPerUser > 0 THEN
			-- select indObjUsers users and create #indObjPerUser objectives for each
			FOR owner IN 
				EXECUTE
					'SELECT u."ID" AS id, u."DISPLAY_NAME" AS displayName, COUNT(o."OWNER_ID") userObjCnt FROM 
						"'||prefix||'UP_USERS" u LEFT JOIN "'||prefix||'UP_OBJECTIVES" o ON u."ID" = o."OWNER_ID" 
						WHERE u."STATUS" = $1 GROUP BY u."ID", u."DISPLAY_NAME" ORDER BY userObjCnt ASC LIMIT $2 OFFSET $3'
				USING 0, indObjUsers, 0
			LOOP
				-- find team obj ids to link to ind objs
				teamObjIds := '{}';
				teamObjTitles := '{}';
				-- RAISE NOTICE 'objective for = %', owner.id;
				FOR obj IN 
					EXECUTE
						'SELECT o."ID" AS id, o."TITLE" AS title FROM "'||prefix||'UP_OBJECTIVES" o
							JOIN "'||prefix||'UP_USER_TEAMS" ut ON o."TEAM_ID" = ut."TEAM_ID"
							WHERE o."IS_DELETED" = $1 AND o."OBJECTIVE_TYPE" = $2 AND ut."USER_ID" = $3'
					USING false, 2, owner.id
				LOOP
					teamObjIds := array_append(teamObjs, obj.id::int);
					teamObjTitles := array_append(teamObjTitles, obj.title::varchar);
				END LOOP;
				FOR i IN 1..indObjPerUser LOOP
					objTitle := 'Ind objective '||i||' for '||owner.displayName;
					objDesc := 'Ind objective desc '||i||' for '||owner.displayName;
					objId := createObj(objTitle, objDesc, 0, cycle.id, cycle.title, date(cycle.startDate), 
							date(cycle.endDate), owner.id, owner.displayName, null, null, labelsCnt, labelIds, 
							projectKeys, projectIds, maxissues, baseUrl, prefix);
					-- link individual objective to team objective
					countVar := array_length(teamObjIds, 1);
					IF countVar > 0 THEN
						SELECT FLOOR(random()* (countVar-1 + 1) + 1)::int into randomNum;
						sourceId := teamObjIds[randomNum];
						sourceTitle := teamObjTitles[randomNum];
						PERFORM createAlignment(owner.id::int, objId, objTitle, sourceId, sourceTitle, prefix);
					END IF;
					RAISE NOTICE 'created ind objective = %', objCount;
					objCount := objCount +1;
				END LOOP;
			END LOOP;
		END IF;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createObj(title varchar(255), message text, objType int, cycleId bigint, 
	cycleTitle varchar(255), startDate timestamp without time zone, endDate timestamp without time zone, 
	ownerId bigint, ownerDispName varchar(255), teamId bigint, teamName varchar(255), labelsCnt int, labelIds int[], 
	projectKeys varchar(255)[], projectIds numeric[], maxissues numeric[],
	baseUrl text, prefix varchar(255)) RETURNS int AS $$
	DECLARE
		objId int;
		objStatus int;
		historyJson text;
		randomNum int;
	BEGIN
		objStatus := 30;
		EXECUTE
			'INSERT INTO "'||prefix||'UP_OBJECTIVES" ("TITLE", "MESSAGE", "OBJECTIVE_TYPE", "OWNER_ID", 
				"TEAM_ID", "STATUS", "OBJECTIVE_CYCLE_ID", "START_DATE", "DUE_DATE", "SHARED_WITH", "PROGRESS_PERCENTAGE", 
				"IS_DELETED", "CONF_STATUS", "CREATED", "CREATED_BY", "MODIFIED", "MODIFIED_BY")
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)'
		USING title, message, objType, ownerId, teamId, objStatus, cycleId, startDate, endDate, 1, 0,
			false, 4, now(), 'System', now(), 'System';
		EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_OBJECTIVES_ID_seq"'')' INTO objId;
		-- create obj history
		historyJson := '{"value":[{"field":"id","new":"'||objId||'"}';
		historyJson := historyJson || ',{"field":"title","new":"'||title||'"}';
		historyJson := historyJson || ',{"field":"description","new":"'||message||'"}';
		historyJson := historyJson || ',{"field":"status","new":"'||objStatus||'"}';
		historyJson := historyJson || ',{"field":"isDeleted","new":"false"}';
		historyJson := historyJson || ',{"field":"owner","new":{"id":'||ownerId||',"name":"'||ownerDispName||'"}}';
		historyJson := historyJson || ',{"field":"objectiveCycle","new":{"id":'||cycleId||',"name":"'||cycleTitle||'"}}';
		historyJson := historyJson || ',{"field":"visibility","new":"1"},{"field":"progress","new":"0.0"}';
		historyJson := historyJson || ',{"field":"type","new":"'||objType||'"},{"field":"confStatus","new":"4"}';
		historyJson := historyJson || ',{"field":"dueDate","new":"'||TO_CHAR(endDate :: DATE, 'dd-mm-yyyy')||'"}';
		IF objType = 1 THEN
			historyJson := historyJson || ',{"field":"team","new":{"id":'||teamId||',"name":"'||teamName||'"}}';
		END IF;
		historyJson := historyJson || ']}';
		PERFORM createObjHistory(ownerId::int, objId, null, 'C', 1, historyJson, prefix);
		-- link random label
		IF labelsCnt > 0 THEN
			SELECT FLOOR(random() * (labelsCnt-1 + 1) + 1)::int INTO randomNum;
			EXECUTE
				'INSERT INTO "'||prefix||'UP_OBJ_LABELS"("LABEL_ID", "OBJECTIVE_ID") VALUES ($1, $2)'
			USING labelIds[randomNum], objId;
		END IF;
		-- create Krs
		PERFORM createKr(objId, ownerId::int, ownerDispName, startDate, endDate, projectKeys, projectIds, maxissues, baseUrl, prefix);
		RETURN objId;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createObjHistory(userId int, objId int, krId int, action varchar(1), hisType int,
	historyJson text, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		hisRevId int;
	BEGIN
		hisRevId := createHistoryRevision(userId, prefix);
		EXECUTE
			'INSERT INTO "'||prefix||'UP_OBJ_HIS" ("OBJ_ID", "KR_ID", "REV_ID", "TYPE", "ACTION", "VALUE")
			VALUES ($1, $2, $3, $4, $5, $6)'
		USING objId, krId, hisRevId, hisType, action, historyJson;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createKr(objId int, ownerId int, ownerDispName varchar(255),
    startDate timestamp without time zone, 	dueDate timestamp without time zone, 
	projectKeys varchar(255)[], projectIds numeric[], 
	maxissues numeric[], baseUrl text, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		noOfKrs int;
		projectkey varchar(255);
		krType int;
		indexNum int;
		targetVal numeric;
		issueDetails text;
		issue RECORD;
		issueId int;
		resolution int;
		countVar int;
		startInd int;
		maxIssueNum int;
		projectId numeric;
		isComplete boolean;
		krTitle varchar(255);
		iconUrl text;
		krOwnerId int;
		krId int;
		historyJson text;
	BEGIN
		-- randomly create max 3 key results
		SELECT FLOOR(random() * (3-0 + 1) + 0)::int INTO noOfKrs;
		IF noOfKrs > 0 THEN
			EXECUTE
				'SELECT COUNT(*) FROM "'||prefix||'UP_OBJ_KEY_RESULTS" 
					WHERE "IS_DELETED" = $1 AND "OBJECTIVE_ID" = $2'
			USING false, objId INTO indexNum;
			FOR i IN 1..noOfKrs LOOP
				indexNum := indexNum + 1;
				-- randomly select kr type out of (metric, todo and issue)
				SELECT FLOOR(random() * (2-0 + 1) + 0)::int INTO krType;
				krOwnerId := ownerId;
				targetVal := 100; 
				krTitle := 'Metric ' || i || ' for OBJ-' || objId;
				IF krType = 1 THEN
					targetVal := 1; 
					krTitle := 'TODO ' || i || ' for OBJ-' || objId;
				END IF;
				issueDetails := null;
				issueId := null;
				IF krType = 2 THEN
					countVar := array_length(projectIds, 1);
					IF countVar > 0 THEN
						SELECT FLOOR(random() * (countVar-1 + 1) + 1)::int INTO startInd;
						projectId := projectIds[startInd];
						maxIssueNum := maxissues[startInd];
						projectKey := projectKeys[startInd];
						SELECT FLOOR(random() * (maxIssueNum-1 + 1) + 1)::int into startInd;
						SELECT i."id" AS id, i."summary" AS summary, i."issuenum" AS issuenum, 
							i."resolution" AS resolution, i."duedate" AS dueDate, i."assignee" AS assignee,
							t."pname" AS issueType, t."iconurl" AS iconUrl, t."avatar" AS avatarId,
							s."pname" AS statusName, s."statuscategory" AS categoryId INTO issue
							FROM "jiraissue" i LEFT JOIN "issuetype" t
							ON i."issuetype" = t."id" LEFT JOIN "issuestatus" s
							ON i."issuestatus" = s."id" 
							WHERE i."project" = projectId and i."issuenum" = startInd;
						krTitle := projectKey || '-' || issue.issuenum;
						dueDate := issue.dueDate;
						issueId := issue.id;
						krOwnerId := getIdFromKey(issue.assignee, prefix);
						issueDetails := '{"id":' || issue.id;
						isComplete := false;
						resolution := issue.resolution;
						IF NOT NULL resolution THEN
							isComplete := true;
						END IF;
						issueDetails := issueDetails || ',isComplete:' || isComplete;
						issueDetails := issueDetails || ',"key":"' || krTitle || '"';
						issueDetails := issueDetails || ',"issueSummary":"' || issue.summary || '"';
						issueDetails := issueDetails || ',"issueTypeName":"' || issue.issueType || '"';
						iconUrl := issue.iconUrl;
						IF NOT NULL iconUrl THEN
							iconUrl := baseUrl || issue.iconUrl;
						ELSE
							iconUrl := baseUrl || '/secure/viewavatar?size=xsmall&avatarId=' || issue.avatarId || '&avatarType=issuetype';
						END IF;
						issueDetails := issueDetails || ',"issueTypeIcon":"' || iconUrl || '"';
						issueDetails := issueDetails || ',"statusName":"' || issue.statusName || '"';
						issueDetails := issueDetails || ',"statusCategoryColor":"' || getCategoryColor(issue.categoryId) || '"}';
					ELSE
						krType := 0; -- set kr type to metric
					END IF;	
				END IF;
				EXECUTE
					'INSERT INTO "'||prefix||'UP_OBJ_KEY_RESULTS" ("TITLE", "OBJECTIVE_ID", "OKR_TYPE", "IS_DELETED", 
						"ORIGINAL_VALUE", "CURRENT_VALUE", "TARGET_VALUE", "WEIGHTAGE", "ISSUE_ID", "ISSUE_DETAILS", 
						"INDEX_NUMBER", "OWNER_ID", "START_DATE", "DUE_DATE", "CONF_STATUS", "REMINDER_FREQUENCY", "PROGRESS_PERCENTAGE",
						"CREATED", "CREATED_BY", "MODIFIED", "MODIFIED_BY") 
					VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21)'
				USING krTitle, objId, krType, false, 0, 0, targetVal, 5, issueId, issueDetails, 
					indexNum, krOwnerId, startDate, dueDate, 4, 0, 0, now(), 'System', now(), 'System';
				EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_OBJ_KEY_RESULTS_ID_seq"'')' INTO krId;
				-- create kr history
				historyJson := '{"value":[{"field":"id","new":"'||krId||'"}';
				historyJson := historyJson || ',{"field":"title","new":"'||krTitle||'"}';
				historyJson := historyJson || ',{"field":"description","new":""}';
				historyJson := historyJson || ',{"field":"isDeleted","new":"false"}';
				IF NOT NULL dueDate THEN
					historyJson := historyJson || ',{"field":"dueDate","new":"'||TO_CHAR(dueDate :: DATE, 'dd-mm-yyyy')||'"}';
				END IF;
				historyJson := historyJson || ',{"field":"type","new":"'||krType||'"},{"field":"confStatus","new":"4"}';
				IF NOT NULL krOwnerId THEN
					historyJson := historyJson || ',{"field":"owner","new":{"id":'||krOwnerId||',"name":"'||ownerDispName||'"}}';
				END IF;	
				IF krType = 2 THEN
					historyJson := historyJson || ',{"field":"issueDetails","new":"'||issueDetails||'"}';
				END IF;
				historyJson := historyJson || ',{"field":"originalValue","new":"0.0"}';
				historyJson := historyJson || ',{"field":"currentValue","new":"0.0"}';
				historyJson := historyJson || ',{"field":"targetValue","new":"'||targetVal||'"}';
				historyJson := historyJson || ',{"field":"weightage","new":"5"}';
				historyJson := historyJson || ',{"field":"confStatus","new":"4"}]}';
				PERFORM createObjHistory(ownerId::int, objId, krId, 'C', 2, historyJson, prefix);
				-- create kr actions
				IF krType != 2 THEN
					PERFORM createActions(ownerId::int, krId, projectKeys, projectIds, maxissues, baseUrl, prefix);
				END IF;
			END LOOP;
		END IF;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getIdFromKey(assignee varchar(255), prefix varchar(255)) RETURNS int AS $$
	DECLARE
		userId int;
	BEGIN
		EXECUTE
			'SELECT "ID" FROM "'||prefix||'UP_USERS" WHERE "KEY" = $1 LIMIT $2'
		USING assignee, 1 INTO userId;
		RETURN userId;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION getCategoryColor(categoryId numeric) RETURNS varchar AS $$
	DECLARE
		statusCategoryColor varchar(255);
	BEGIN
		statusCategoryColor := 'medium-gray'; -- for categoryId = 1
		IF categoryId = 2 THEN
			statusCategoryColor := 'blue-gray';
		ELSEIF categoryId = 3 THEN
			statusCategoryColor := 'yellow';
		ELSEIF categoryId = 4 THEN
			statusCategoryColor := 'green';
		END IF;
		RETURN statusCategoryColor;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createActions(userId int, krId int, projectKeys varchar(255)[], 
	projectIds numeric[], maxissues numeric[], baseUrl text, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		noOfActions int;
		countVar int;
		startInd int;
		issueDetails text;
		issue RECORD;
		issueId int;
		resolution int;
		projectkey varchar(255);
		maxIssueNum int;
		projectId numeric;
		isComplete boolean;
		iconUrl text;
		ownerId int;
		historyJson text;
		actionId int;
		dueDate timestamp without time zone; 
	BEGIN
		-- randomly create max 2 actions of type issue
		SELECT FLOOR(random() * (2-0 + 1) + 0)::int INTO noOfActions;
		countVar := array_length(projectIds, 1);
		IF noOfActions > 0 AND countVar > 0 THEN
			FOR i IN 1..noOfActions LOOP
				SELECT FLOOR(random() * (countVar-1 + 1) + 1)::int INTO startInd;
				projectId := projectIds[startInd];
				maxIssueNum := maxissues[startInd];
				projectKey := projectKeys[startInd];
				SELECT FLOOR(random() * (maxIssueNum-1 + 1) + 1)::int into startInd;
				SELECT i."id" AS id, i."summary" AS summary, i."issuenum" AS issuenum, 
					i."resolution" AS resolution, i."duedate" AS dueDate, i."assignee" AS assignee,
					t."pname" AS issueType, t."iconurl" AS iconUrl, t."avatar" AS avatarId,
					s."pname" AS statusName, s."statuscategory" AS categoryId INTO issue
					FROM "jiraissue" i LEFT JOIN "issuetype" t
					ON i."issuetype" = t."id" LEFT JOIN "issuestatus" s
					ON i."issuestatus" = s."id" 
					WHERE i."project" = projectId and i."issuenum" = startInd;
				issueDetails := '{"id":' || issue.id;
				isComplete := false;
				resolution := issue.resolution;
				IF NOT NULL resolution THEN
					isComplete := true;
				END IF;
				issueDetails := issueDetails || ',isComplete:' || isComplete;
				issueDetails := issueDetails || ',"key":"' || projectKey || '-' || issue.issuenum || '"';
				issueDetails := issueDetails || ',"issueSummary":"' || issue.summary || '"';
				issueDetails := issueDetails || ',"issueTypeName":"' || issue.issueType || '"';
				iconUrl := issue.iconUrl;
				IF NOT NULL iconUrl THEN
					iconUrl := baseUrl || issue.iconUrl;
				ELSE
					iconUrl := baseUrl || '/secure/viewavatar?size=xsmall&avatarId=' || issue.avatarId || '&avatarType=issuetype';
				END IF;
				issueDetails := issueDetails || ',"issueTypeIcon":"' || iconUrl || '"';
				issueDetails := issueDetails || ',"statusName":"' || issue.statusName || '"';
				issueDetails := issueDetails || ',"statusCategoryColor":"' || getCategoryColor(issue.categoryId) || '"}';
				ownerId := getIdFromKey(issue.assignee, prefix);
				EXECUTE
					'INSERT INTO "'||prefix||'UP_OBJ_KR_ACTIONS" ("TITLE", "ISSUE_ID", "ISSUE_DETAILS", 
						"ACTION_TYPE", "KEY_RESULT_ID", "OWNER_ID", "DUE_DATE", "IS_DELETED",
						"PROGRESS_PERCENTAGE", "CREATED", "CREATED_BY", "MODIFIED", "MODIFIED_BY")
					VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)'
				USING projectKey || '-' || issue.issuenum, issue.id, issueDetails, 0, krId, ownerId, 
					issue.dueDate, false, 0, now(), 'System', now(), 'System';
				EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_OBJ_KR_ACTIONS_ID_seq"'')' INTO actionId;
				-- create kr action history
				historyJson := '{"value":[{"field":"id","new":"'||actionId||'"}';
				historyJson := historyJson || ',{"field":"title","new":"'|| projectKey || '-' || issue.issuenum|| '"}';
				historyJson := historyJson || ',{"field":"isDeleted","new":"false"}';
				dueDate := issue.dueDate;
				IF NOT NULL dueDate THEN
					historyJson := historyJson || ',{"field":"dueDate","new":"'||dueDate||'"}';
				END IF;
				historyJson := historyJson || ',{"field":"type","new":"0"}';
				historyJson := historyJson || ',{"field":"issueDetails","new":"'||issueDetails||'"}]}';
				PERFORM createObjHistory(userId, null, krId, 'C', 3, historyJson, prefix);
			END LOOP;		
		END IF;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createAlignment(userId int, linkId int, linkTitle varchar(255), 
	sourceId int, sourceTitle varchar(255), prefix varchar(255)) RETURNS void AS $$
	DECLARE
		alignmentId int;
		hisRevId int;
		historyJson text;
	BEGIN
		EXECUTE
			'INSERT INTO "'||prefix||'UP_OBJ_LINKS" ("LINK_ID", "SOURCE_ID", "WEIGHTAGE", 
				"CREATED", "CREATED_BY", "MODIFIED", "MODIFIED_BY") 
			VALUES ($1, $2, $3, $4, $5, $6, $7)'
		USING linkId, sourceId, 5, now(), 'System', now(), 'System';
		EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_OBJ_LINKS_ID_seq"'')' INTO alignmentId;
		-- create history for both source / link objectives
		hisRevId := createHistoryRevision(userId, prefix);
		historyJson := '{"value":[{"field":"weightage","new":"5"}';
		historyJson := historyJson || ',{"field":"sourceObjective","new":{"id":'||sourceId||',"name":"'||sourceTitle||'"}}';
		historyJson := historyJson || ',{"field":"linkObjective","new":{"id":'||linkId||',"name":"'||linkTitle||'"}}]}';
		EXECUTE
			'INSERT INTO "'||prefix||'UP_OBJ_HIS" ("OBJ_ID", "REV_ID", "TYPE", "ACTION", "VALUE")
			VALUES ($1, $2, $3, $4, $5)'
		USING sourceId, hisRevId, 5, 'C', historyJson;
		EXECUTE
			'INSERT INTO "'||prefix||'UP_OBJ_HIS" ("OBJ_ID", "REV_ID", "TYPE", "ACTION", "VALUE")
			VALUES ($1, $2, $3, $4, $5)'
		USING linkId, hisRevId, 5, 'C', historyJson;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createFeedbacks(feedbackUsers int, feedbackPerUser int, projectKeys varchar(255)[], 
	projectIds numeric[], maxissues numeric[], prefix varchar(255)) RETURNS void AS $$
	DECLARE
		totalTags int;
		countVar int;
		totalUsers int;
		tagIds int[];
		tag RECORD;
		tagId int;
		creator RECORD;
		receiver RECORD;
		linkToResourceType varchar(255)[];
		userObjCnt int;
		userKrCnt int;
		randomNum int;
		sharedWith int;
		created timestamp without time zone;
		message text;
		resourceType varchar(255);
		resourceId varchar(255);
		maxIssueNum int;
		projectKey varchar(255);
		feedbackId int;
		managerId int;
		activityType int;
		totalFb int;
	BEGIN
		IF feedbackUsers > 0 AND feedbackPerUser > 0 THEN
			-- link to either issue or obj or kr
			linkToResourceType := ARRAY['INDEPENDANT', 'ISSUE'];--, 'OBJECTIVE', 'KEY_RESULT'];
			-- total users to randomly select receiver
			EXECUTE
				'SELECT COUNT(*) FROM "'||prefix||'UP_USERS" WHERE "STATUS" = $1'
			USING 0 INTO totalUsers;
			-- tags
			tagIds := '{}';
			totalTags := 0;
			FOR tag IN 
				EXECUTE	'SELECT "ID" FROM "'||prefix||'UP_FB_TAG"' 
			LOOP
				tagIds := array_append(tagIds, tag."ID"::int);
				totalTags := totalTags + 1;
			END LOOP;
			IF (totalTags > 0) THEN
				-- select users who have not yet given any feedback first
				totalFb := 0;
				FOR creator IN 
					EXECUTE
						'SELECT u."ID" AS id, COUNT(f."CREATOR_ID") AS userFBCnt FROM "'||prefix||'UP_USERS" u
							LEFT JOIN "'||prefix||'UP_FB" f ON u."ID" = f."CREATOR_ID"
							WHERE u."STATUS" = $1 GROUP BY u."ID" ORDER BY userFBCnt ASC LIMIT $2 OFFSET $3'
					USING 0, feedbackUsers, 0
				LOOP
					totalFb := totalFb + 1;
					RAISE NOTICE 'feedback number = %', totalFb;
					
					FOR i IN 1..feedbackPerUser LOOP
						-- select receiver
						SELECT FLOOR(random() * ((totalUsers-1)-0 + 1) + 0)::int INTO randomNum;
						EXECUTE
							'SELECT "ID" AS id, "MANAGER_ID" AS mngrId, "DISPLAY_NAME" AS displayName
								FROM "'||prefix||'UP_USERS" WHERE "STATUS" = $1 AND "ID" <> $2
								ORDER BY "ID" ASC LIMIT $3 OFFSET $4'
						USING 0, creator.id, 1, randomNum INTO receiver;
						-- randomly select sharedWith
						SELECT FLOOR(random() * (3-1 + 1) + 1)::int INTO sharedWith;
						-- randomly select a tag
						SELECT FLOOR(random() * (totalTags-1 + 1) + 1)::int INTO randomNum;
						tagId := tagIds[randomNum];
						-- select random date in last 365 days
						SELECT FLOOR(random() * 365)::int INTO randomNum;
						created := CURRENT_DATE - randomNum + CURRENT_TIME;
						-- randomly select issue or obj or kr to link to feedback
						SELECT floor(random() * (2-1 + 1) + 1)::int into randomNum;
						resourceType := linkToResourceType[randomNum];
						IF resourceType = 'INDEPENDANT' THEN
							resourceType := null;
							resourceId := null;
						ELSEIF resourceType = 'ISSUE' THEN
							countVar := array_length(projectIds, 1);
							IF countVar > 0 THEN
								SELECT FLOOR(random() * (countVar-1 + 1) + 1)::int INTO randomNum;
								maxIssueNum := maxissues[randomNum];
								projectKey := projectKeys[randomNum];
								SELECT FLOOR(random() * (maxIssueNum-1 + 1) + 1)::int INTO randomNum;
								resourceId := projectKey||'-'||randomNum;
							ELSE
								resourceType := null;
								resourceId := null;
							END IF;
						ELSEIF resourceType = 'OBJECTIVE' THEN
							EXECUTE
								'SELECT COUNT(*) FROM "'||prefix||'UP_OBJECTIVES" 
									WHERE "OWNER_ID" = $1 AND "IS_DELETED" = $2'
							USING receiver.id, false INTO countVar;
							IF countVar > 0 THEN
								SELECT FLOOR(random() * ((countVar-1)-0 + 1) + 0)::int INTO randomNum;
								EXECUTE
									'SELECT "ID"::text FROM "'||prefix||'UP_OBJECTIVES"
										WHERE "OWNER_ID" = $1 AND "IS_DELETED" = $2 LIMIT $3 OFFSET $4'
								USING receiver.id, false, 1, randomNum INTO resourceId;
							ELSE
								resourceType := null;
								resourceId := null;
							END IF;
						ELSEIF resourceType = 'KEY_RESULT' THEN
							EXECUTE
								'SELECT COUNT(*) FROM "'||prefix||'UP_OBJ_KEY_RESULTS" 
									WHERE "OWNER_ID" = $1 AND "IS_DELETED" = $2'
							USING receiver.id, false INTO countVar;
							IF countVar > 0 THEN
								SELECT FLOOR(random() * ((countVar-1)-0 + 1) + 0)::int INTO randomNum;
								EXECUTE
									'SELECT "ID"::text INTO resourceId FROM "'||prefix||'UP_OBJ_KEY_RESULTS" 
									WHERE "OWNER_ID" = $1 AND "IS_DELETED" = $2 LIMIT $3 OFFSET $4'
								USING receiver.id, false, 1, randomNum INTO resourceId;
							ELSE
								resourceType := null;
								resourceId := null;
							END IF;
						END IF;
						message :=  '{"version":1,"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Test feedback '||i||' for user '||receiver.displayName||'"}]}]}';
						EXECUTE
							'INSERT INTO "'||prefix||'UP_FB" ("MESSAGE", "CREATOR_ID", "RECEIVER_ID",
								"FEEDBACK_TAG_ID", "SHARED_WITH", "RESOURCE_ID", "RESOURCE_TYPE", 
								"CREATED", "CREATED_BY", "MODIFIED", "MODIFIED_BY")
							VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)'
						USING message, creator.id, receiver.id, tagId, sharedWith, resourceId, resourceType,
							now(), 'System', now(), 'System';
						EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_FB_ID_seq"'')::int' INTO feedbackId;
						-- create user / team sharings 
						IF sharedWith = 3 THEN
							managerId := 0;
							IF receiver.mngrId IS NOT NULL AND receiver.mngrId <> creator.id THEN
								-- share with receivers manager
								EXECUTE
									'INSERT INTO "'||prefix||'UP_FB_USERS" ("FEEDBACK_ID", "USER_ID")
									VALUES ($1, $2)'
								USING feedbackId, receiver.mngrId;
								managerId := receiver.mngrId;
							END IF;
							-- create some sharings
							IF (i % 2) = 0 THEN
								-- share with user's teams
								EXECUTE
									'INSERT INTO "'||prefix||'UP_FB_TEAMS" ("FEEDBACK_ID", "TEAM_ID")
									SELECT $1, t."ID" FROM "'||prefix||'UP_TEAMS" t
									JOIN "'||prefix||'UP_USER_TEAMS" ut ON t."ID" = ut."TEAM_ID"
									WHERE t."DELETED" = $2 AND ut."USER_ID" = $3'
								USING feedbackId, false, receiver.id;								
							ELSE
								-- share with some of his team members
								EXECUTE
									'SELECT COUNT(*) FROM "'||prefix||'UP_USERS" u 
										JOIN "'||prefix||'UP_USER_TEAMS" ut ON u."ID" = ut."USER_ID"
										WHERE u."STATUS" = $1 AND ut."TEAM_ID" IN
										(SELECT t."ID" FROM "'||prefix||'UP_TEAMS" t JOIN 
										"'||prefix||'UP_USER_TEAMS" ut1 ON t."ID" = ut1."TEAM_ID"
										WHERE t."DELETED" = $2 AND ut1."USER_ID" = $3)'
								USING 0, false, receiver.id INTO countVar;
								
								SELECT floor(random() * ((countVar-1)-0 + 1) + 0)::int into randomNum;
								
								EXECUTE
									'INSERT INTO "'||prefix||'UP_FB_USERS" ("FEEDBACK_ID", "USER_ID")
									SELECT $1, u."ID" FROM "'||prefix||'UP_USERS" u 
									JOIN "'||prefix||'UP_USER_TEAMS" ut ON u."ID" = ut."USER_ID"
									WHERE u."STATUS" = $2 AND u."ID" <> $3 AND ut."TEAM_ID" IN
									(SELECT t."ID" FROM "'||prefix||'UP_TEAMS" t JOIN 
									"'||prefix||'UP_USER_TEAMS" ut1 ON t."ID" = ut1."TEAM_ID"
									WHERE t."DELETED" = $4 AND ut1."USER_ID" = $5)
									OFFSET $6 LIMIT $7'
								USING feedbackId, 0, managerId, false, receiver.id, randomNum, 4;
							END IF;
						END IF;
						activityType := 1;
						IF sharedWith = 2 THEN
							activityType := 2;
						END IF;
						PERFORM createActivity((creator.id)::int, feedbackId, (null)::int, 1, activityType, prefix);
					END LOOP;
				END LOOP;
			ELSE
				raise EXCEPTION 'There are no feedback tags defined create few first and then try feedback create';
			END IF;
		END IF;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createActivity(actorId int, entityId int, childEntityId int, entityType int, 
	activityType int, prefix varchar(255)) RETURNS void AS $$
	BEGIN
		EXECUTE
			'INSERT INTO "'||prefix||'UP_ACTIVITY" ("ACTOR_ID", "ENTITY_ID", "CHILD_ENTITY_ID", "ENTITY_TYPE", "ACTIVITY_TYPE")
			VALUES ($1, $2, $3, $4, $5)'
		USING actorId, entityId, childEntityId, entityType, activityType;
	END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION createFormFields(formId int, prefix varchar(255)) RETURNS void AS $$
	DECLARE
		fieldSetting text;
		fieldType text;
		section int;
		sequenceNo int;
	BEGIN
		IF formId > 0 THEN 
			section := 1;
			sequenceNo := 1;
			fieldType := 'SectionStart';
			fieldSetting := '{"en":{"text":"Technical","description":"","classes":["leftAlign","topAlign"],"styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":1},"styles":{"color":"default","backgroundColor":"default"}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 2;
			fieldType := 'SingleLineText';
			fieldSetting := '{"en":{"label":"Single Line Text 1","value":"","description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"groupId":1},"_persistable":true,"required":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 3;
			fieldType := 'ParagraphText';
			fieldSetting := '{"en":{"label":"Paragraph Text 1","value":"","description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"groupId":1},"_persistable":true,"required":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 4;
			fieldType := 'Date';
			fieldSetting := '{"en":{"label":"Date 1","value":"","description":"","dateFormat":"dd/mm/yyyy","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"groupId":1},"_persistable":true,"required":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 5;
			fieldType := 'MultipleChoice';
			fieldSetting := '{"en":{"label":"Multiple Choice 1","value":"","choices":[{"id":1,"name":"Choice 1","checked":false},{"id":2,"name":"Choice 2","checked":false},{"id":3,"name":"Choice 3","checked":false}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":1},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 6;
			fieldType := 'CheckBox';
			fieldSetting := '{"en":{"label":"Check Box 1","value":"","choices":[{"id":0,"name":"Choice 1","checked":false},{"id":1,"name":"Choice 2","checked":false},{"id":2,"name":"Choice 3","checked":false}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"groupId":1},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 7;
			fieldType := 'StarRatings';
			fieldSetting := '{"en":{"label":"Star Ratings 1","value":"","min":0,"max":5,"choices":[{"id":1,"name":"Consistently below expectations","checked":false,"value":1},{"id":2,"name":"Below expectations","checked":false,"value":2},{"id":3,"name":"Meets expectations","checked":false,"value":3},{"id":4,"name":"Exceeds expectations","checked":false,"value":4},{"id":5,"name":"Consistently exceeds expectations","checked":false,"value":5}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":1},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 8;
			fieldType := 'DropDown';
			fieldSetting := '{"en":{"label":"Dropdown 2","value":"","choices":[{"id":1,"name":"Menu 1","checked":false},{"id":2,"name":"Menu 2","checked":false},{"id":3,"name":"Menu 3","checked":false}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":1},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 9;
			fieldType := 'YesNo';
			fieldSetting := '{"en":{"label":"Yes / No 1","value":"","choice":[{"id":0,"name":"Yes","checked":false},{"id":1,"name":"No","checked":false}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"groupId":1},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 10;
			fieldType := 'OpinionScale';
			fieldSetting := '{"en":{"label":"Opinion Scale 1","value":"","start":0,"end":5,"min":3,"max":11,"current":5,"choices":[{"id":0,"name":"Not likely","checked":false},{"id":1,"name":"Extremely likely","checked":false}],"list":[{"id":0},{"id":1},{"id":2},{"id":3},{"id":4}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":1},"_persistable":true,"required":true,"addCommentBox":true,"startScaleOne":false,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			section := 2;
			sequenceNo := 1;
			fieldType := 'StarRatings';
			fieldSetting := '{"en":{"label":"Star Ratings 1","value":"","min":0,"max":5,"choices":[{"id":1,"name":"Consistently below expectations","checked":false,"value":1},{"id":2,"name":"Below expectations","checked":false,"value":2},{"id":3,"name":"Meets expectations","checked":false,"value":3},{"id":4,"name":"Exceeds expectations","checked":false,"value":4},{"id":5,"name":"Consistently exceeds expectations","checked":false,"value":5}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			section := 3;
			sequenceNo := 1;
			fieldType := 'StarRatings';
			fieldSetting := '{"en":{"label":"Star Ratings 1","value":"","min":0,"max":5,"choices":[{"id":1,"name":"Consistently below expectations","checked":false,"value":1},{"id":2,"name":"Below expectations","checked":false,"value":2},{"id":3,"name":"Meets expectations","checked":false,"value":3},{"id":4,"name":"Exceeds expectations","checked":false,"value":4},{"id":5,"name":"Consistently exceeds expectations","checked":false,"value":5}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			section := 4;
			sequenceNo := 1;
			fieldType := 'StarRatings';
			fieldSetting := '{"en":{"label":"Star Ratings 1","value":"","min":0,"max":5,"choices":[{"id":1,"name":"Consistently below expectations","checked":false,"value":1},{"id":2,"name":"Below expectations","checked":false,"value":2},{"id":3,"name":"Meets expectations","checked":false,"value":3},{"id":4,"name":"Exceeds expectations","checked":false,"value":4},{"id":5,"name":"Consistently exceeds expectations","checked":false,"value":5}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 2;
			fieldType := 'DropDown';
			fieldSetting := '{"en":{"label":"Dropdown 1","value":"","choices":[{"id":1,"name":"Menu 1","checked":false},{"id":2,"name":"Menu 2","checked":false},{"id":3,"name":"Menu 3","checked":false}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 3;
			fieldType := 'OpinionScale';
			fieldSetting := '{"en":{"label":"Opinion Scale 1","value":"","start":0,"end":5,"min":3,"max":11,"current":5,"choices":[{"id":0,"name":"Not likely","checked":false},{"id":1,"name":"Extremely likely","checked":false}],"list":[{"id":0},{"id":1},{"id":2},{"id":3},{"id":4}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"startScaleOne":false,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			section := 5;
			sequenceNo := 1;
			fieldType := 'StarRatings';
			fieldSetting := '{"en":{"label":"Star Ratings 1","value":"","min":0,"max":5,"choices":[{"id":1,"name":"Consistently below expectations","checked":false,"value":1},{"id":2,"name":"Below expectations","checked":false,"value":2},{"id":3,"name":"Meets expectations","checked":false,"value":3},{"id":4,"name":"Exceeds expectations","checked":false,"value":4},{"id":5,"name":"Consistently exceeds expectations","checked":false,"value":5}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 2;
			fieldType := 'YesNo';
			fieldSetting := '{"en":{"label":"Yes / No 1","value":"","choice":[{"id":0,"name":"Yes","checked":false},{"id":1,"name":"No","checked":false}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

			sequenceNo := 3;
			fieldType := 'OpinionScale';
			fieldSetting := '{"en":{"label":"Opinion Scale 1","value":"","start":0,"end":5,"min":3,"max":11,"current":5,"choices":[{"id":0,"name":"Not likely","checked":false},{"id":1,"name":"Extremely likely","checked":false}],"list":[{"id":0},{"id":1},{"id":2},{"id":3},{"id":4}],"description":"","styles":{"fontFamily":"default","fontSize":"default","fontStyles":[0,0,0]},"score":true,"weightage":5,"groupId":0},"_persistable":true,"required":true,"addCommentBox":true,"startScaleOne":false,"restriction":"no","styles":{"label":{"color":"default","backgroundColor":"default"},"value":{"color":"default","backgroundColor":"default"},"description":{"color":"777777","backgroundColor":"default"}}}';
			EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_FIELD" ("CREATED", "CREATED_BY", "FIELD_SETTINGS", "FIELD_TYPE", "FORM_ID",  "MODIFIED", "MODIFIED_BY", "NAME", "SECTION", "SEQUENCE_NO") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)'
			USING now(), 'admin', fieldSetting, fieldType, formId, now(), 'admin', NULL, section, sequenceNo;

		END IF;
	END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION createDistributions(formId int, prefix varchar(255), distributionPerTemplate int, usersPerDistribution int) RETURNS void 
AS $$
	DECLARE
		distributionId int;
		hrRec record;
		hrIds int[];
		reviewerRec record;
		reviewerIds int[];
		userRec record;
		randomHrId int;
		randomReviewerId int;
		randomNumber int;
	BEGIN
		IF distributionPerTemplate > 0 THEN 
			FOR i IN 1..distributionPerTemplate LOOP
				RAISE NOTICE 'creat distribution = %', i;
				EXECUTE 'INSERT INTO "'||prefix||'UP_FRM_DIST" ("IS_RESPONSE_VIEW", 
				"IS_VIEW_PERMISSION", "REVIEW_PERIOD_END", "REVIEW_PERIOD_START", "SCHEDULE_DATE", 
				"START_DATE", "VIEW_PERMISSION", "DESCRIPTION", "REASON_FOR_ARCHIVAL",
				"ANONYMITY", "AUTO_CLOSE", "CREATED", 
				"CREATED_BY", "END_DATE", "FORM_ID", "IS_DELETED", 
				"MODIFIED", "MODIFIED_BY", "OPEN_TILL", "STATUS", 
				"TITLE", "WORKFLOW_ID") 
				VALUES (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)'
				USING '{"formAnonymity11":true,"formAnonymity12":true,"formAnonymity21":true,"formAnonymity22":true,"formAnonymity31":true,"formAnonymity32":true}', 
				true, now(),'admin', CURRENT_DATE +30, formId, false, now(),'admin', CURRENT_DATE +20, 0, 'Distribution '||i,  3;
						
				EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_FRM_DIST_ID_seq"'')' INTO distributionId;

				IF usersPerDistribution > 0 THEN
					-- get array of hr user
					FOR hrRec IN
						EXECUTE 
						'SELECT rle."USER_ID", random() as rnd FROM "'||prefix||'UP_USER_ROLES" rle, "'||prefix||'UP_USERS" usr 
						WHERE rle."USER_ID" = usr."ID" AND usr."STATUS" = 0 
						AND rle."ROLE_ID" in (SELECT "ID" FROM "'||prefix||'UP_ROLES" WHERE "NAME" = ''HR_ADMIN'')
						order by rnd LIMIT 5'
					LOOP
						hrIds := array_append(hrIds, hrRec."USER_ID"::int);
					END LOOP;
					-- RAISE NOTICE 'hr Ids = %', hrIds;
					FOR reviewerRec IN
						EXECUTE 
						'SELECT rle."USER_ID", random() as rnd FROM "'||prefix||'UP_USER_ROLES" rle, "'||prefix||'UP_USERS" usr 
						WHERE rle."USER_ID" = usr."ID" AND usr."STATUS" = 0 
						AND rle."ROLE_ID" in (SELECT "ID" FROM "'||prefix||'UP_ROLES" WHERE "NAME" = ''USER'')
						order by rnd LIMIT 5'
					LOOP
						reviewerIds := array_append(reviewerIds, reviewerRec."USER_ID"::int);
					END LOOP;
					-- RAISE NOTICE 'reviewer Ids = %', reviewerIds;
					
					FOR userRec IN
						EXECUTE 
						'SELECT rle."USER_ID", random() as rnd FROM "'||prefix||'UP_USER_ROLES" rle, "'||prefix||'UP_USERS" usr 
						WHERE rle."USER_ID" = usr."ID" AND usr."STATUS" = 0 
						AND rle."ROLE_ID" in (SELECT "ID" FROM "'||prefix||'UP_ROLES" WHERE "NAME" = ''USER'')
						AND NOT (rle."USER_ID" = ANY($1)) 
						order by rnd LIMIT $2'
						USING reviewerIds, usersPerDistribution
					LOOP
						-- RAISE NOTICE 'user Id = %', userRec."USER_ID";
						randomNumber:=floor((random()*array_length(hrIds,1)));
						-- RAISE NOTICE 'randomNumber = %', randomNumber;									   
						randomHrId := hrIds[randomNumber+1];
						randomNumber:=floor((random()*array_length(reviewerIds,1)));	
						-- RAISE NOTICE 'randomNumber = %', randomNumber;
						randomReviewerId := reviewerIds[randomNumber+1];
						-- RAISE NOTICE 'randomHrId = % randomReviewerId =%',randomHrId, randomReviewerId;
						 
						
						EXECUTE	'INSERT INTO "'||prefix||'UP_FRM_DIST_USR" (
						"ABOUT_USER_STATUS", "IS_CLOSED", "REVIEWER_EMAIL", "REVIEWER_STATUS", "WORKFLOW_ENTRY_ID", 
						"ASSIGNED_TO_ID", "CREATED", "CREATED_BY", "DISTRIBUTION_ID", "FORM_ID", 
						"HR_RESPONSE_BY_ID", "IS_DELETED", "MODIFIED", "MODIFIED_BY", 
						"OPEN_TILL", "RESPONDER_TYPE", "REVIEWER_ID", 
						"SHARE_WITH_ABOUT", "STATUS", "USER_ID") 
						VALUES (NULL, NULL, NULL, NULL, NULL, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 
							$12, $13, $14, $15)'
						USING userRec."USER_ID", now(), 'admin', distributionId, formId, randomHrId, 
						false, now(), 'admin', CURRENT_DATE +20, 4, randomReviewerId, true, 1, userRec."USER_ID" ;
					END LOOP;
						
				END IF;

			END LOOP;
		END IF;
	END;
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION createFormTemplates(templates int, prefix varchar(255), distributionPerTemplate int, usersPerDistribution int) RETURNS void AS $$
	DECLARE
		startAt int;
		maxResults int;
		uCount int;
		userId int;
		templateFormId int;
	BEGIN
		IF templates > 0 THEN 
			EXECUTE 'SELECT COUNT(*) FROM "'||prefix||'UP_USERS" WHERE "STATUS" = 0' INTO uCount ;
			FOR i IN 1..templates LOOP
				EXECUTE
					'INSERT INTO "'||prefix||'UP_FRM_FORM" ("CREATED", "CREATED_BY", "DESCRIPTION", 
					"FORM_TEMPLATE_ID", "IS_DELETED", "MODIFIED", "MODIFIED_BY", "MODIFIED_BY_ID", "NAME", 
					"SETTINGS", "STATUS", "WORKFLOW_ID") VALUES ($1, $2, $3, $4, $5, $6, $7, NULL, $8, $9, $10, $11)'
					USING now(), 'admin', '{"version":1,"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"this is appraisal form"}]}]}', 
					1, false, now(), 'admin',  'Appraisal Form '||i , 
					'{"en":{"name":"Appraisal Form","description":"{\"version\":1,\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"this is appraisal form\"}]}]}","otherSettings":{"INCLUDE_OBJECTIVES":{"show":false,"label":"Include Objectives","value":true},"SHOW_FEEDBACK_TAB":{"show":true,"label":"Show Feedback Tab","value":true},"SHOW_ISSUES_TAB":{"show":true,"label":"Show Issues Tab","value":true},"SHOW_NOTES_TAB":{"show":false,"label":"Show Notes Tab","value":true},"scores":[{"section":2,"score":45.0,"weightage":10.0,"groupScores":[{"group":1,"score":80.0,"weightage":20.0,"groupWeightage":5.0}]},{"section":3,"score":45.0,"weightage":10.0,"groupScores":[{"group":1,"score":80.0,"weightage":20.0,"groupWeightage":5.0}]},{"section":4,"score":65.0,"weightage":15.0},{"section":5,"score":50.0,"weightage":10.0}]},"classes":["leftAlign"],"heading":"h1","styles":{"fontFamily":"-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, Oxygen, Ubuntu, \"Fira Sans\", \"Droid Sans\", \"Helvetica Neue\", sans-serif","fontSize":"16","fontStyles":[1,0,0]}},"styles":{"color":"rgb(0, 0, 0)","backgroundColor":"rgba(0, 0, 0, 0)"}}',
					0, 3;
				EXECUTE 'SELECT CURRVAL(''"'||prefix||'UP_FRM_FORM_ID_seq"'')' INTO templateFormId;

				IF distributionPerTemplate > 0 THEN
					FOR i IN 1..distributionPerTemplate LOOP
					RAISE NOTICE 'Template number = %', i;
					-- create form fields	
					PERFORM createFormFields(templateFormId, prefix);
					-- create distribution for templates
					PERFORM createDistributions(templateFormId, prefix , distributionPerTemplate , usersPerDistribution);
					END LOOP;
				END IF;

			END LOOP;
		END IF;
	END;
$$ LANGUAGE plpgsql;


DO $$ 
DECLARE
	importUsers boolean; -- if true import users from Jira into UpRaise
	teams int; -- no. of teams to create
	companyObj int; -- no.of company objectives to create
	teamObjTeams int; -- no of teams for which team objectives to create
	teamObjPerTeam int;
	indObjUsers int; -- no of users for which individual objectives to create
	indObjPerUser int;
	feedbackUsers int; -- no of users for which feedbacks to create
	feedbackPerUser int;
	baseUrl text; -- Url of your jira instance 
	templates int; -- no of forms
    distributionPerTemplate int; -- number of distributions per template
    usersPerDistribution int; -- users per distribution
	prefix varchar(255); -- table name prefix of app
BEGIN
	importUsers := false;
	teams := 500;
	companyObj := 500;
	teamObjTeams := 500;
	teamObjPerTeam := 3;
	indObjUsers := 2500;
	indObjPerUser := 4;
	feedbackUsers := 3000;
	feedbackPerUser := 5;
	templates :=10;
	distributionPerTemplate :=5;
	usersPerDistribution :=150;
	baseUrl := 'jira-loadb-j48ewjv5z51d-1617510938.ap-southeast-1.elb.amazonaws.com';
	prefix := 'AO_EB0AB3_';
	PERFORM generateData(importUsers, teams, companyObj, teamObjTeams, teamObjPerTeam,
		indObjUsers, indObjPerUser, feedbackUsers, feedbackPerUser, baseUrl, templates, distributionPerTemplate, usersPerDistribution, prefix);
	DROP FUNCTION generateData(importUsers boolean, teams int, companyObj int, teamObjTeams int, teamObjPerTeam int,
		indObjUsers int, indObjPerUser int, feedbackUsers int, feedbackPerUser int, baseUrl text, templates int, distributionPerTemplate int, usersPerDistribution int, prefix varchar(255));
	DROP FUNCTION importUsers(importUsers boolean, prefix varchar(255));
	DROP FUNCTION checkUserExists(userKey varchar(255), prefix varchar(255));
	DROP FUNCTION createHistoryRevision(userId int, prefix varchar(255));
	DROP FUNCTION createTeams(teams int, prefix varchar(255));
	DROP FUNCTION createObjectives(companyObj int, teamObjTeams int, teamObjPerTeam int,
		indObjUsers int, indObjPerUser int, projectKeys varchar(255)[], projectIds numeric[], maxissues numeric[],
		baseUrl text, prefix varchar(255));
	DROP FUNCTION createObj(title varchar(255), message text, objType int, cycleId bigint, 
		cycleTitle varchar(255), startDate timestamp without time zone, endDate timestamp without time zone, 
		ownerId bigint, ownerDispName varchar(255), teamId bigint, teamName varchar(255), labelsCnt int, labelIds int[], 
		projectKeys varchar(255)[], projectIds numeric[], maxissues numeric[], baseUrl text, prefix varchar(255));
	DROP FUNCTION createObjHistory(userId int, objId int, krId int, action varchar(1), hisType int,
		historyJson text, prefix varchar(255));
	DROP FUNCTION createKr(objId int, ownerId int, ownerDispName varchar(255), startDate timestamp without time zone, 
		dueDate timestamp without time zone, projectKeys varchar(255)[], projectIds numeric[], 
		maxissues numeric[], baseUrl text, prefix varchar(255));
	DROP FUNCTION getIdFromKey(assignee varchar(255), prefix varchar(255));
	DROP FUNCTION getCategoryColor(categoryId numeric);
	DROP FUNCTION createAlignment(userId int, linkId int, linkTitle varchar(255), 
		sourceId int, sourceTitle varchar(255), prefix varchar(255));
	DROP FUNCTION createActions(userId int, krId int, projectKeys varchar(255)[], 
		projectIds numeric[], maxissues numeric[], baseUrl text, prefix varchar(255));
	DROP FUNCTION createFeedbacks(feedbackUsers int, feedbackPerUser int, projectKeys varchar(255)[], 
		projectIds numeric[], maxissues numeric[], prefix varchar(255));
	DROP FUNCTION createActivity(actorId int, entityId int, childEntityId int, entityType int, 
		activityType int, prefix varchar(255));
	DROP FUNCTION createFormFields(formId int, prefix varchar(255));
	DROP FUNCTION createDistributions(formId int, prefix varchar(255), distributionPerTemplate int, usersPerDistribution int);
	DROP FUNCTION createFormTemplates(templates int, prefix varchar(255), distributionPerTemplate int, usersPerDistribution int);

END $$;