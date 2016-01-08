<?php

ini_set('memory_limit', -1);

$autoloader = include_once("vendor/autoload.php");

if ( ! $autoloader ) 
{
	echo "\n\n  vendor/autoload.php could not be found. Did you run `php composer.phar install`?\n\n"; exit;
}

$sierra = new Sierra('sierra-db.your.edu', 'db_user', 'db_pass');

$timestamp = time() - (1*24*60*60); // yesterday
$location = 'data';

$results = $sierra->exportRecordsModifiedAfter($timestamp, $location);