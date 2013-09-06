<?php

ini_set('memory_limit', -1);

require_once 'File/Marc.php';
require_once 'lib/Sierra.php';

$sierra = new Sierra('sierra-db.your.edu', 'db_user', 'db_pass');

$timestamp = time() - (1*24*60*60); // yesterday
$location = 'data';

$results = $sierra->exportRecordsModifiedAfter($timestamp, $location);