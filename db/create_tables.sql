------------------------
-- MISSING FUNCTIONALITY
------------------------

-- group intents into 1 class for a specific model...


--------
-- Setup
--------

\c opringle;
DROP DATABASE IF EXISTS atlas_new;

CREATE DATABASE atlas_new;
\c atlas_new;
CREATE SCHEMA data;
SET search_path = data, public;

CREATE USER dbadmin WITH SUPERUSER LOGIN PASSWORD 'dbadmin';

---------------------
-- Intents & contexts: allows intents to be available in certain contexts and output certain contexts
---------------------

CREATE TABLE intents (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) NOT NULL,
    description VARCHAR(1000) NOT NULL,
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    webhook_for_intent BOOLEAN NOT NULL DEFAULT FALSE,
    webhook_for_slot_filling BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT no_duplicate_intent_names UNIQUE (name)
);


CREATE TABLE contexts (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) NOT NULL,
    description VARCHAR(1000) NOT NULL,
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT no_duplicate_context_names UNIQUE (name)
);


CREATE TABLE intent_input_contexts (
    intent VARCHAR(10) REFERENCES intents (name),
    input_context VARCHAR(10) REFERENCES contexts (name),
    PRIMARY KEY (intent, input_context)
);


CREATE TABLE intent_output_contexts (
    intent VARCHAR(10) REFERENCES intents (name),
    output_context VARCHAR(10) REFERENCES contexts (name),
    lifespan INTEGER NOT NULL,
    PRIMARY KEY (intent, output_context)
);

-----------------------------
-- Intents & training phrases: supports inter annotator agreement, intent annotation, context specific models, classifier logs, classifier test scores
-----------------------------

CREATE TABLE languages (
    id SERIAL PRIMARY KEY,
    code VARCHAR(2) UNIQUE NOT NULL,
    name VARCHAR(10) UNIQUE NOT NULL
);


CREATE TABLE locales (
    id SERIAL PRIMARY KEY,
    code VARCHAR(2) UNIQUE NOT NULL,
    language_code VARCHAR(2) REFERENCES languages (code) NOT NULL
);


CREATE TABLE environments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) UNIQUE NOT NULL --eg dominos-prod, mturk
);


CREATE TABLE phrases (
    id SERIAL PRIMARY KEY,
    phrase VARCHAR(1000),
    locale_code VARCHAR(2) REFERENCES locales (code),
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    session_id INTEGER,
    environment VARCHAR(10) REFERENCES environments (name) NOT NULL,
    UNIQUE (phrase, id)
);


CREATE TABLE annotators (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) UNIQUE
);


CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) UNIQUE
);


CREATE TABLE agents (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) UNIQUE
);


CREATE TABLE customer_agents (
    customer VARCHAR(10) REFERENCES customers (name),
    agent VARCHAR(10) REFERENCES agents (name),
    PRIMARY KEY (customer, agent)
);


CREATE TABLE intent_classifiers (
    id SERIAL PRIMARY KEY,
    agent VARCHAR(10) REFERENCES agents (name),
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    input_context VARCHAR(10) REFERENCES contexts(name),
    macro_f1 REAL,
    micro_f1 REAL,
    macro_precision REAL,
    micro_precision REAL,
    macro_recall REAL,
    micro_recall REAL
);


CREATE TABLE intents_phrases_models (
    phrase_id INTEGER REFERENCES phrases (id),
    classifier_id INTEGER REFERENCES intent_classifiers (id),
    intent VARCHAR(10) REFERENCES intents (name),
    classifier_output REAL NOT NULL,
    PRIMARY KEY (phrase_id, classifier_id, intent),
    CONSTRAINT allowed_model_output CHECK (classifier_output >= 0 AND classifier_output <= 1)
);


CREATE TABLE intents_phrases_annotators (
    phrase_id INTEGER NOT NULL,
    phrase VARCHAR(1000) UNIQUE,
    intent VARCHAR(10) REFERENCES intents (name),
    annotator VARCHAR(10) REFERENCES annotators (name),
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    FOREIGN KEY (phrase_id, phrase) REFERENCES phrases (id, phrase),
    PRIMARY KEY (phrase, annotator)
);


----------------------
-- Intents & customers: supports multiple agents per customer, multi language agents, state specific classifiers
----------------------


CREATE TABLE agents_locales (
    agent VARCHAR(10) REFERENCES agents (name),
    locale_code VARCHAR(2) REFERENCES locales (code),
    PRIMARY KEY (agent, locale_code)
);


CREATE TABLE agent_intents (
    agent VARCHAR(10) REFERENCES agents (name),
    intent VARCHAR(10) REFERENCES intents (name),
    PRIMARY KEY (agent, intent)
);


----------------
-- Translations: supports a single translation per utterance and language. No duplicate translations. Responses can be in various languages.
----------------

CREATE TABLE phrases_translations (
    phrase_id INTEGER NOT NULL,
    phrase VARCHAR(1000) NOT NULL,
    machine_translation VARCHAR(1000),
    to_language VARCHAR(2) REFERENCES languages (code),
    PRIMARY KEY (phrase, to_language),
    FOREIGN KEY (phrase_id, phrase) REFERENCES phrases (id, phrase)
);


CREATE TABLE responses (
    id SERIAL PRIMARY KEY,
    response VARCHAR(1000) UNIQUE,
    locale_code VARCHAR(2) REFERENCES locales (code),
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL
);

-- allows us to choose a different response based on locale within a single agent
CREATE TABLE response_translations (
    response VARCHAR(1000) REFERENCES responses (response),
    translation VARCHAR(1000),
    to_locale VARCHAR(2) REFERENCES locales (code),
    PRIMARY KEY (response, to_locale)
);


----------------
-- Exact matches: supports exact matching between a phrase and a response id in an agent
----------------

CREATE TABLE response_exact_match (
    agent VARCHAR(10) REFERENCES agents (name),
    phrase_id INTEGER NOT NULL,
    phrase VARCHAR(1000) NOT NULL,
    response_id INTEGER REFERENCES responses (id),
    PRIMARY KEY (agent, phrase),
    FOREIGN KEY (phrase_id, phrase) REFERENCES phrases (id, phrase)
);

----------------------
-- Intents & entities: allows compound entities to be defined
----------------------

-- the thing we train NER to extract (eg product)
CREATE TABLE entities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) UNIQUE,
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL
);

-- the thing we want to associate the value with (eg checking account)
-- some entities will have no reference values, eg @date
CREATE TABLE reference_values (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) UNIQUE,
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL
);


-- exact substrings that are a given reference_value (eg tfsa account)
CREATE TABLE synonyms (
    id SERIAL PRIMARY KEY,
    name VARCHAR(10) UNIQUE,
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE entity_reference_values (
    reference_value VARCHAR(10) REFERENCES reference_values (name),
    entity VARCHAR(10) REFERENCES entities (name),
    PRIMARY KEY (reference_value, entity)
);


CREATE TABLE value_synonyms (
    reference_value VARCHAR(10) REFERENCES reference_values (name),
    synonym VARCHAR(10) REFERENCES synonyms (name),
    PRIMARY KEY (reference_value, synonym)
);


CREATE TABLE intents_entities (
    intent VARCHAR(10) REFERENCES intents (name),
    entity VARCHAR(10) REFERENCES entities (name),
    PRIMARY KEY (intent, entity)
);


-------------
-- Responses: for flexible conversations, responses cannot be tied to intents or entities... instead we think through each conversational flow & based on current entities/intents write a response.
-------------

CREATE OR REPLACE FUNCTION CheckIntentWebhookOff(intent VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE webhook_status BOOLEAN;
BEGIN
        SELECT webhook_for_intent INTO webhook_status
        FROM intents
        WHERE intent = $1;

        RETURN NOT webhook_status;
END;
$$  LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = data;


CREATE OR REPLACE FUNCTION CheckEntityWebhookOff(intent VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE webhook_status BOOLEAN;
BEGIN
        SELECT webhook_for_slot_filling INTO webhook_status
        FROM intents
        WHERE intent = $1;

        RETURN NOT webhook_status;
END;
$$  LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = data;


CREATE TABLE  no_webhook_responses (
    agent VARCHAR(10) REFERENCES agents (name),
    intent VARCHAR(10) REFERENCES intents (name),
    response VARCHAR(1000) REFERENCES responses (response),
    CONSTRAINT webhook_is_off CHECK (CheckIntentWebhookOff(intent) = TRUE)
);


CREATE TABLE  no_webhook_slot_prompts (
    agent VARCHAR(10) REFERENCES agents (name),
    intent VARCHAR(10) REFERENCES intents (name),
    entity VARCHAR(10) REFERENCES entities (name),
    response VARCHAR(1000) REFERENCES responses (response),
    CONSTRAINT webhook_is_off CHECK (CheckEntityWebhookOff(intent) = TRUE)
);


------------------------
---- Entities & Phrases:
------------------------

CREATE TABLE entity_taggers (
    id SERIAL PRIMARY KEY,
    language_code VARCHAR(2) REFERENCES languages (code),
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    macro_f1 REAL,
    micro_f1 REAL,
    macro_precision REAL,
    micro_precision REAL,
    macro_recall REAL,
    micro_recall REAL
);


CREATE TABLE entities_phrases_taggers (
    phrase_id INTEGER NOT NULL,
    phrase VARCHAR(1000) NOT NULL,
    tagger_id INTEGER REFERENCES entity_taggers (id) NOT NULL,
    entity VARCHAR(10) REFERENCES entities (name) NOT NULL,
    substring_range INT4RANGE,
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    PRIMARY KEY (tagger_id, phrase, substring_range),
    FOREIGN KEY (phrase_id, phrase) REFERENCES phrases (id, phrase)
);


CREATE TABLE entities_phrases_annotators (
    phrase_id INTEGER NOT NULL,
    phrase VARCHAR(1000) NOT NULL,
    entity VARCHAR(10) REFERENCES entities (name) NOT NULL,
    substring_range INT4RANGE,
    annotator VARCHAR(10) REFERENCES annotators (name) NOT NULL,
    creation_date TIMESTAMP WITH TIME ZONE NOT NULL,
    PRIMARY KEY (phrase, annotator, substring_range),
    FOREIGN KEY (phrase_id, phrase) REFERENCES phrases (id, phrase)
);

--
---- each entity has a list of 1 or more values
---- each value can be EITHER text or a list of 1 or more other entities
---- if the value is text, the value can have a list of 0 or more synonyms
--
--entities --
--values  -- field for text names & field for entities
--synonyms --
--text_values_synonyms
--
--CREATE TABLE entity_types (
--    id SERIAL PRIMARY KEY,
--    name VARCHAR(10) UNIQUE NOT NULL,
--    description VARCHAR(1000) UNIQUE NOT NULL
--);
--
--
--CREATE TABLE entities (
--    id SERIAL PRIMARY KEY,
--    name VARCHAR(10) UNIQUE NOT NULL,
--    type VARCHAR(10) REFERENCES entity_types (name)
--);
--
--
--CREATE TABLE synonyms (
--    id SERIAL PRIMARY KEY,
--    name VARCHAR(10) UNIQUE NOT NULL,
--    entity VARCHAR(10) REFERENCES entities (name)
--);
--
--
--CREATE TABLE regex (
--    id SERIAL PRIMARY KEY,
--    name VARCHAR(10) UNIQUE NOT NULL,
--    entity VARCHAR(10) REFERENCES entities (name)
--);
--
---- if you define synonyms for an entity, the reference value is returned for them & they cannot use other entities
---- entities can consist of other entities
---- therefore, there is a many to many relationship between entities and themselves
---- for example {'geo': {'New York': ['NYC', 'New York City']}}
---- the reference_value is then the entity eg {'geo': 'New York'}
---- from here you need to resolve the reference value to something the system can easily digest eg {'geo': [40.7128, 74.0060]}
--
--CREATE TABLE entities_reference_values (
--    parent_entity VARCHAR(10) REFERENCES entities (name),
--    child_entity VARCHAR(10) REFERENCES entities (name),
--
--)
--
---- entities have detection methods: regex, exact match, machine learning
---- entities have types: composite, heirarchical, regex, exact_matched & simple
--
--E1 E2
--1 2
--1 3
--1 4
--2 2
--2 3
--2 4
--
--
--
--

---------------------------------
---- Finn-DL logging & annotation
---------------------------------
--
---- could also include deployed (BOOL), env (prod) etc, however this would be more challenging to maintain
--CREATE TABLE intent_classifiers (
--    id INTEGER NOT NULL,
--    model_name character varying(10000) REFERENCES utterances (utterance),
--    macro_f1 real
--);
--
---- logs from the intent classifer will consist of many intent/confidence_scores per utterance
--CREATE TABLE intent_classifier_logs (
--    session_id INTEGER NOT NULL,
--    utterance character varying(10000) REFERENCES utterances (utterance),
--    intent character varying(100) REFERENCES intents (intent_name),
--    model_id integer REFERENCES intent_classifiers (id),
--    model_confidence real,
--    request_time  timestamp with time zone,
--    exact_match BOOLEAN NOT NULL,
--    fallback_intent BOOLEAN NOT NULL,
--    CONSTRAINT consistent_model_output UNIQUE (utterance, model_id, intent_name, model_confidence)
--    CONSTRAINT model_confidence CHECK (model_confidence >= 0 AND model_confidence <= 1)
--);
--
---- annotations for the intent classifier will consist of a single annotation per utterance/annotator.
---- training data can be queried by number of annotations now :)
---- although annotations are stored here, what is the process of annotating? the user should see each utterance once, however, here there are many rows for each annotator
--CREATE TABLE intent_classifier_annotations (
--    utterance character varying(10000) REFERENCES intent_classifier_logs (utterance),
--    intent_name character varying(100) REFERENCES intents (intent_name),
--    annotator_id integer REFERENCES roles?? --check user exists somehow
--    confirmed BOOLEAN DEFAULT FALSE
--    confirmation_date  timestamp with time zone,
--    CONSTRAINT confirm_utterance_once UNIQUE (utterance, confirmed, annotator_id)
--    CONSTRAINT confirmed_has_annotator CHECK ( (NOT confirmed) OR (annotator_id IS NOT NULL) )
--);
--
-----------------------------
---- NER logging & annotation (in progress)
-----------------------------
--
--CREATE TABLE entity_tagger_logs (
--    session_id INTEGER NOT NULL,
--    utterance character varying(10000) REFERENCES utterances (utterance),
--    model_id integer REFERENCES entity_models (model_id),
--    substring_range int4range
--    extracted_text character varying(10000)
--    entity_kind character varying(100) REFERENCES entity_kinds (entity_kind),
--    prediction_time  timestamp with time zone,
--    CONSTRAINT consistent_model_output UNIQUE (utterance, model_id, entity_kind, substring_range)
--);
--
--
--CREATE TABLE entity_tagger_annotations (
--    utterance character varying(10000) REFERENCES intent_classifier_logs (utterance),
--    intent_name character varying(100) REFERENCES intents (intent_name),
--    annotator_id integer REFERENCES roles?? --check user exists somehow
--    confirmed BOOLEAN DEFAULT FALSE
--    confirmation_date  timestamp with time zone,
--    CONSTRAINT duplicate_annotations UNIQUE (utterance, intent_name, annotator_id)
--    CONSTRAINT confirmed_has_annotator CHECK ( (NOT confirmed) OR (annotator_id IS NOT NULL) )
--);
--
--
