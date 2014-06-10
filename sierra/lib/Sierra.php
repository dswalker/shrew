<?php

/**
 * Sierra access object
 *
 * @author David Walker <dwalker@calstate.edu>
 */

class Sierra
{
	/**
	 * @var string
	 */
	private $host;
	
	/**
	 * @var string
	 */
	private $username;
	
	/**
	 * @var string
	 */
	private $password;
	
	/**
	 * @var string
	 */
	private $port;
	
	/**
	 * @var string
	 */
	private $dbname;	
	
	/**
	 * @var PDO
	 */
	
	private $pdo;
	
	/**
	 * @var int
	 */
	
	private $total;
	
	/**
	 * Create new Sierra access object
	 * 
	 * @param string $host      hostname, sierra-db.example.edu
	 * @param string $username  db username
	 * @param string $password  db user's password
	 * @param string $port      [optional] default '1032'
	 * @param string $dbname    [optional] default 'iii'
	 */
	
	public function __construct($host, $username, $password, $port = '1032', $dbname = 'iii')
	{
		$this->host = $host;
		$this->username = $username;
		$this->password = $password;
		$this->port = $port;
		$this->dbname = $dbname;
	}
	
	/**
	 * Export bibliographic records (and attached item records) modified AFTER the supplied date
	 * 
	 * @param int $timestamp    unix timestamp
	 * @param string $location  path to file to create
	 */
	
	public function exportRecordsModifiedAfter($timestamp, $location)
	{
		$date = gmdate("Y-m-d H:i:s", $timestamp);
		
		// record id's for those records modified since our supplied date
		
		$results = $this->getModifiedRecordData($date);
		
		// make 'em
		
		$this->createRecords($location, 'modified', $results);
	}

	/**
	 * Export bibliographic records deleted AFTER the supplied date
	 *
	 * @param int $timestamp    unix timestamp
	 * @param string $location  path to file to create
	 */
	
	public function exportRecordsDeletedAfter($timestamp, $location)
	{
		$date = gmdate("Y-m-d H:i:s", $timestamp);
	
		// record id's for those records modified since our supplied date
	
		$results = $this->getDeletedRecordData($date);
	
		// make 'em
	
		$this->createRecords($location, 'modified', $results, true);
	}	
	
	/**
	 * Export all bibliographic records (and attached item records) out of the Innovative system
	 * 
	 * @param string $location  path to file to create
	 */
	
	public function exportRecords($location)
	{
		// get all record id's
		
		$results = $this->getAllRecordData();
		
		// make 'em
		
		$this->createRecords($location, 'full', $results);
	}
	
	/**
	 * Fetch an individual record
	 * 
	 * @param string $id
	 * @return File_MARC_Record|null
	 */
	
	public function getBibRecord($id)
	{
		// bib record query
		
		$sql = trim("
			SELECT
				bib_view.id,
				bib_view.bcode1,
				bib_view.bcode2,
				bib_view.bcode3,
				bib_view.cataloging_date_gmt,
				varfield_view.marc_tag,
				varfield_view.marc_ind1,
				varfield_view.marc_ind2,
				varfield_view.field_content,
				varfield_view.varfield_type_code,
				leader_field.*
			FROM
				sierra_view.bib_view
			INNER JOIN 
				sierra_view.varfield_view ON bib_view.id = varfield_view.record_id
			LEFT JOIN
				sierra_view.leader_field ON bib_view.id = leader_field.record_id
			WHERE
				bib_view.record_num = '$id'
			ORDER BY 
				marc_tag
		");
		
		$results = $this->getResults($sql);
		
		if ( count($results) == 0 )
		{
			return null;
		}
		
		$record = new File_MARC_Record();
	
		// let's parse a few things, shall we
		
		$result = $results[0];
		
		$internal_id = $result[0]; // internal postgres id
		
		// leader
		
		// 0000's here get converted to correct lengths by File_MARC
		
		$leader = '00000'; // 00-04 - Record length
		$leader .= $this->getLeaderValue($result,'record_status_code'); // 05 - Record status
		$leader .= $this->getLeaderValue($result,'record_type_code'); // 06 - Type of record
		$leader .= $this->getLeaderValue($result,'bib_level_code'); // 07 - Bibliographic level
		$leader .= $this->getLeaderValue($result,'control_type_code'); // 08 - Type of control
		$leader .= $this->getLeaderValue($result,'char_encoding_scheme_code'); // 09 - Character coding scheme
		$leader .= '2'; // 10 - Indicator count
		$leader .= '2'; // 11 - Subfield code count
		$leader .= '00000'; // 12-16 - Base address of data
		$leader .= $this->getLeaderValue($result,'encoding_level_code'); // 17 - Encoding level
		$leader .= $this->getLeaderValue($result,'descriptive_cat_form_code'); // 18 - Descriptive cataloging form
		$leader .= $this->getLeaderValue($result,'multipart_level_code'); // 19 - Multipart resource record level
		$leader .= '4'; // 20 - Length of the length-of-field portion
		$leader .= '5'; // 21 - Length of the starting-character-position portion
		$leader .= '0'; // 22 - Length of the implementation-defined portion
		$leader .= '0'; // 23 - Undefined
		
		$record->setLeader($leader);
		
		// innovative bib record fields

		$bib_field = new File_MARC_Data_Field('907');
		$record->appendField($bib_field);
		$bib_field->appendSubfield(new File_MARC_Subfield('a', $this->getFullRecordId($id)));
		
		// cataloging info fields
		
		$bib_field = new File_MARC_Data_Field('998');
		$record->appendField($bib_field);
		
		$bib_field->appendSubfield(new File_MARC_Subfield('c', trim($result['cataloging_date_gmt'])));
		$bib_field->appendSubfield(new File_MARC_Subfield('d', trim($result['bcode1'])));
		$bib_field->appendSubfield(new File_MARC_Subfield('e', trim($result['bcode2'])));
		$bib_field->appendSubfield(new File_MARC_Subfield('f', trim($result['bcode3'])));
		
		// marc fields
		
		foreach ( $results as $result )
		{
			try
			{
				// skip missing tags and 'old' 9xx tags that mess with the above
				
				if ( $result['marc_tag'] == null || $result['marc_tag'] == '907' || $result['marc_tag'] == '998')
				{
					continue;
				}
				
				// control field
				
				if ( (int) $result['marc_tag'] < 10 )
				{
					$control_field = new File_MARC_Control_Field($result['marc_tag'], $result['field_content']);
					$record->appendField($control_field);
				}
				
				// data field
				
				else 
				{
					$data_field = new File_MARC_Data_Field($result['marc_tag']);
					$data_field->setIndicator(1, $result['marc_ind1']);
					$data_field->setIndicator(2, $result['marc_ind2']);
					
					$content = $result['field_content'];
					
					$content_array  = explode('|', $content);
					
					foreach ( $content_array as $subfield )
					{
						$code = substr($subfield, 0, 1);
						$data = substr($subfield, 1);
						
						if ( $code == '')
						{
							continue;
						}
						
						$subfield = new File_MARC_Subfield($code, trim($data));
						$data_field->appendSubfield($subfield);
					}
					
					$record->appendField($data_field);
				}
			}
			catch ( File_MARC_Exception $e )
			{
				trigger_error( $e->getMessage(), E_USER_WARNING );
			}
		}
		
		// location codes
		
		$sql = trim("
			SELECT location_code
			FROM
				sierra_view.bib_record_location
			WHERE
				bib_record_id = '$internal_id'
		");
		
		$results = $this->getResults($sql);
		
		if ( count($results) > 0 )
		{
			$location_record = new File_MARC_Data_Field('907');
			
			foreach ( $results as $result )
			{
				$location_record->appendSubfield(new File_MARC_Subfield('b', trim((string)$result['location_code'])));
			}
			
			$record->appendField($location_record);
		}
		
		// item records
		
		$sql = trim("
			SELECT item_view.*
			FROM 
				sierra_view.bib_view,
				sierra_view.item_view,
				sierra_view.bib_record_item_record_link
			WHERE 
				bib_view.record_num = '$id' AND
				bib_view.id = bib_record_item_record_link.bib_record_id AND
				item_view.id = bib_record_item_record_link.item_record_id				
		");
		
		$results = $this->getResults($sql);
		
		foreach ( $results as $result )
		{
			$item_record = new File_MARC_Data_Field('945');
			$item_record->appendSubfield(new File_MARC_Subfield('l', trim($result['location_code'])));
			
			$record->appendField($item_record);
		}
		
		return $record;
	}
	
	/**
	 * Create MARC records from a set of record id's
	 *
	 * @param string $location  path to file to create
	 * @param string $name      name of file to create
	 * @param array $results    id query
	 * @param bool $split       [optional] whether split the file into 50,000-record smaller files (default false)
	 * 
	 */
	
	public function createRecords($location, $name, $results, $split = false)
	{
		if (! is_dir($location) )
		{
			throw new Exception("location must be a valid directory, you supplied '$location'");
		}
		
		$this->total = count($results);
		
		// split them into chunks of 100k
		
		$chunks = array_chunk($results, 50000);
		$x = 1; // file number
		$y = 1; // number of records's processed
		
		// file to write to
		
		if ( $split === false )
		{
			$marc21_file = fopen("$location/$name.marc", "wb");
		}
		
		foreach ( $chunks as $chunk )
		{
			// file to write to (if broken into chunks)
			
			if ( $split === true )
			{
				$marc21_file = fopen("$location/$name-$x.marc", "wb");
			}
			
			// create each marc record based on the id
			
			foreach ( $chunk as $result )
			{
				$marc_record = null;
			
				$id = $result['record_num'];
				
				// deleted record
			
				if ( $result['deletion_date_gmt'] != '' )
				{
					$marc_record = $this->createDeletedRecord($id);
				}
				else // active record
				{
					$marc_record = $this->getBibRecord($id);
				}
				
				if ( $marc_record != null )
				{
					fwrite($marc21_file, $marc_record->toRaw());
				}
			
				$this->log("Fetched record '$id' (" . number_format($y) . " of " . number_format($this->total) . ")\n");
				$y++;
			}
			
			if ( $split === true )
			{
				fclose($marc21_file);
			}

			$x++;
			
			// blank this so PDO will create a new connection
			// otherwise after about ~70,000 queries the server 
			// will drop the connection with an error
			
			$this->pdo = null; 
		}
		
		if ( $split === false )
		{
			fclose($marc21_file);
		}
	}
	
	/**
	 * Create a deleted record
	 * 
	 * This is essentially a placeholder record so we have something that represents a
	 * record completely expunged from the system
	 * 
	 * @param int $id
	 */
	
	public function createDeletedRecord($id)
	{
		$record = new File_MARC_Record();
		
		$control_field = new File_MARC_Control_Field('001', "deleted:$id");
		$record->appendField($control_field);
		
		// bib id field
		
		$bib_field = new File_MARC_Data_Field('907');
		$record->appendField($bib_field);
		$bib_field->appendSubfield(new File_MARC_Subfield('a', $this->getFullRecordId($id)));
		
		// mark as deleted
		
		$bib_field = new File_MARC_Data_Field('998');
		$record->appendField($bib_field);
		$bib_field->appendSubfield(new File_MARC_Subfield('f', 'd'));

		return $record;
	}
	
	/**
	 * Return record id (and date information) for bibliographic records modified since the supplied date
	 * 
	 * @return array
	 */

	protected function getModifiedRecordData( $date )
	{
		$sql = trim("
			SELECT
				record_num, record_last_updated_gmt, deletion_date_gmt
			FROM
				sierra_view.record_metadata 
			WHERE
				record_type_code = 'b' AND
				campus_code = '' AND 
				( record_last_updated_gmt > :modified_date OR deletion_date_gmt > :modified_date) 
			ORDER BY
				record_last_updated_gmt DESC NULLS LAST 
		");

		$results = $this->getResults($sql, array(':modified_date' => $date));
		
		return $results;
	}
	
	/**
	 * Return record id (and date information) for bibliographic records modified since the supplied date
	 *
	 * @return array
	 */
	
	protected function getDeletedRecordData( $date )
	{
		$sql = trim("
			SELECT
				record_num, record_last_updated_gmt, deletion_date_gmt
			FROM
				sierra_view.record_metadata
			WHERE
				record_type_code = 'b' AND
				campus_code = '' AND
				deletion_date_gmt > :modified_date
			ORDER BY
				record_last_updated_gmt DESC NULLS LAST
		");
	
		return $this->getResults($sql, array(':modified_date' => $date));
	}	
	
	/**
	 * Return record id (and date information) for all bibliographic records in the system
	 * 
	 * @return array
	 */
	
	protected function getAllRecordData( $limit = null, $offset = 0 )
	{
		$sql = trim("
			SELECT
				record_metadata.record_num, record_metadata.record_last_updated_gmt, record_metadata.deletion_date_gmt
			FROM
				sierra_view.record_metadata,
				sierra_view.bib_view
			WHERE
				record_metadata.record_type_code = 'b' AND
				record_metadata.campus_code = '' AND
				record_metadata.deletion_date_gmt IS NULL AND
				sierra_view.record_metadata.id = sierra_view.bib_view.id
			ORDER BY
				record_last_updated_gmt DESC NULLS LAST
		");

		if ( $limit != null && $offset != 0 )
		{
			$sql .= " LIMIT $limit, $offset";
		}		
		
		return $this->getResults($sql);
	}	

	/**
	 * Fetch results from the database
	 *
	 * @param string $sql    query
	 * @param array $params  [optional] query input paramaters
	 *
	 * @throws Exception
	 * @return array
	 */
	
	protected function getResults($sql, array $params = null)
	{
		$statement = $this->pdo()->prepare($sql);
	
		if ( ! $statement->execute($params) )
		{
			throw new Exception('Could not execute query');
		}
	
		return $statement->fetchAll();
	}
	
	/**
	 * The full record id, including starting period and check digit
	 * 
	 * @param string $id
	 * @return string
	 */
	
	protected function getFullRecordId($id)
	{
		return ".b$id" . $this->getCheckDigit($id);
	}
	
	/**
	 * Calculate Innovative Record number check digit
	 * 
	 * Thanks to mark matienzo (anarchivist) https://github.com/anarchivist/drupal-shrew/
	 * 
	 * @param string $recnum
	 * @return string
	 */
	
	protected function getCheckDigit($recnum) 
	{
		$seq = array_reverse(str_split($recnum));
		$sum = 0;
		$multiplier = 2;
		
		foreach ($seq as $digit)
		{
			$digit *= $multiplier;
			$sum += $digit;
			$multiplier++;
		}
		$check = $sum % 11;
		
		if ($check == 10)
		{
		    return 'x';
		}
		else
		{
    		return strval($check);
    	}
	}
	
	/**
	 * Error logging
	 * 
	 * @param string $message
	 */
	
	protected function log($message)
	{
		echo $message;
	}
	
	/**
	 * Lazy load PDO
	 */
	
	protected function pdo()
	{
		if ( ! $this->pdo instanceof PDO )
		{
			$dsn = 'pgsql:host=' . $this->host . ';' .
				'port=' . $this->port . ';' .
				'dbname=' . $this->dbname . ';' .
				'user=' . $this->username . ';' .
				'password=' . $this->password . ';' . 
				'sslmode=require';

			$this->pdo = new PDO($dsn);
			$this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
		}
		
		return $this->pdo;
	}
	
	/**
	 * Get the value out of the array or return a blank space
	 * @param array $array
	 * @param string $key
	 */
	
	private function getLeaderValue(array $array, $key)
	{
		$value = $array[$key];
		
		if ( $value == "")
		{
			return " ";
		}
		else
		{
			return $value;
		}
	}
}
