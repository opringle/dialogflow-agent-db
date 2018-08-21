# dialogflow-agent-db
a database to store all info required to generate a fully functional dialogflow assistant

- create a db that stores all fields required to upload intents, repsonses, entities etc to an agent



PART 2: SCORE DEVELOPMENT

A. Given what you know about this dataset and the telemetry available to you, program the following score. Your code should take as input the data in the CSV files, and produce as output a score value for each playtest.

SCORING PARAMETERS:

Score Name: Informed Decision Score

Telemetry needed: Which species are displayed, selected, and removed, and in what order? 

Telemetry Strings: 
-score=1 IF edit_action == "include" for "species x" AND edited_species_displayed_ever_prior == TRUE for "species x";
-score=0 IF edit_action == "include" for "species x" AND edited_species_displayed_ever_prior == FALSE for "species x".

Operationalization: Average binary score of whether the item selected was researched or not (0- item selected was not researched, 1- item selected was researched). If a particular species’ inclusion status is edited multiple times, use only the first inclusion to contribute to the score.
