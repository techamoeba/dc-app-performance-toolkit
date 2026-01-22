INSERT INTO "AO_299380_ARN_TEMPLATES" 
("NAME", "SUBJECT", "PROJECT_ID", "TYPE", "BODY", "CREATED", "CREATED_BY", "IS_DELETED") 
SELECT 'Test Template ' || generate_series(1, 500), 
       'Subject ' || generate_series(1, 500), 
       10000, 
       (random() * 5)::int + 1, 
       'Body Content', 
       NOW(), 'admin', false;
	 
	 select * from "AO_299380_ARN_TEMPLATES" 