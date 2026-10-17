UPDATE workflow_entity SET nodes = (SELECT nodes FROM workflow_entity WHERE id = 'YCp5VzHtadiqber1') WHERE id = 'YpNJFblt2FHO2Q9C';
UPDATE workflow_published_version SET nodes = (SELECT nodes FROM workflow_entity WHERE id = 'YCp5VzHtadiqber1') WHERE "workflowId" = 'YpNJFblt2FHO2Q9C';
UPDATE workflow_entity SET active = true WHERE id = 'YpNJFblt2FHO2Q9C';
