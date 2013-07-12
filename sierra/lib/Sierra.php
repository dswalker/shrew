<?php

/**
 * Sierra access object
 *
 * @author David Walker <dwalker@calstate.edu>
 */

class Sierra
{
	/**
	 * @var PDO
	 */
	
	private $pdo;	

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
		$this->pdo = new PDO("pgsql:host=$host;port=$port;dbname=$dbname", $username, $password);
		$this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
	}
	
	/**
	 * Fetch records modified since the given timestamp
	 * 
	 * @param int $timestamp  unix timestamp
	 */
	
	public function getRecordsModifiedSince($timestamp, $location = "modified.marc")
	{
		$date = gmdate("Y-m-d H:i:s", $timestamp);
		
		$marc_records = array();
		
		// we'll get just the record id's for those records
		// modified since our supplied date
		
		$results = $this->getModifiedRecordData($date);
		
		$total = count($results);
		
		if ( $total > 0 )
		{
			$x = 1;
			
			$marc21_file = fopen($location, "wb");
		
			// then create each marc record based on the id
			
			foreach ( $results as $result )
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
					
					// file_put_contents('data/' . $result['record_num'] . '.xml', $marc_record->toXML());
				}
				
				$this->log("Fetching record '$id' ($x of $total)\n");
				$x++;
			}
			
			fclose($marc21_file);
		}
	}
	
	/**
	 * Fetch an individual record
	 * 
	 * @param string $id
	 * @return File_MARC_Record|null
	 */
	
	public function getBibRecord($id)
	{
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
			INNER JOIN
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
	
		// leader
		
		$result = $results[0];
		
		// 0000's here get converted to correct lengths by File_MARC
		
		$leader = '00000'; // 00-04 - Record length
		$leader .= $result['record_status_code']; // 05 - Record status
		$leader .= $result['record_type_code']; // 06 - Type of record
		$leader .= $result['bib_level_code']; // 07 - Bibliographic level
		$leader .= $result['control_type_code']; // 08 - Type of control
		$leader .= $result['char_encoding_scheme_code']; // 09 - Character coding scheme
		$leader .= '2'; // 10 - Indicator count
		$leader .= '2'; // 11 - Subfield code count
		$leader .= '00000'; // 12-16 - Base address of data
		$leader .= $result['encoding_level_code']; // 17 - Encoding level
		$leader .= $result['descriptive_cat_form_code']; // 18 - Descriptive cataloging form
		$leader .= $result['multipart_level_code']; // 19 - Multipart resource record level
		$leader .= '4'; // 20 - Length of the length-of-field portion
		$leader .= '5'; // 21 - Length of the starting-character-position portion
		$leader .= '0'; // 22 - Length of the implementation-defined portion
		$leader .= '0'; // 23 - Undefined	
		
		$record->setLeader($leader);
		
		// innovative bib record fields

		$bib_field = new File_MARC_Data_Field('907');
		$record->appendField($bib_field);
		
		$bib_field->appendSubfield(new File_MARC_Subfield('a', "b$id"));
		// $bib_field->appendSubfield(new File_MARC_Subfield('b', trim($result['record_last_updated_gmt'])));
		
		$bib_field = new File_MARC_Data_Field('998');
		$record->appendField($bib_field);
		
		$bib_field->appendSubfield(new File_MARC_Subfield('c', trim($result['cataloging_date_gmt'])));
		$bib_field->appendSubfield(new File_MARC_Subfield('d', trim($result['bcode1'])));
		$bib_field->appendSubfield(new File_MARC_Subfield('e', trim($result['bcode2'])));
		$bib_field->appendSubfield(new File_MARC_Subfield('f', trim($result['bcode3'])));
		
		// marc fields
		
		foreach ( $results as $result )
		{
			if ( $result['marc_tag'] == null )
			{
				$result['marc_tag'] = 999;
			}
			
			// skip 'old' 9xx tags that mess with the above
			
			if ( $result['marc_tag'] == '907' || $result['marc_tag'] == '998')
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
	 * Create a deleted record
	 * 
	 * @param int $id
	 */
	
	public function createDeletedRecord($id)
	{
		$record = new File_MARC_Record();
		
		// bib id field
		
		$bib_field = new File_MARC_Data_Field('907');
		$record->appendField($bib_field);
		$bib_field->appendSubfield(new File_MARC_Subfield('a', "b$id"));
		
		// mark as deleted
		
		$bib_field = new File_MARC_Data_Field('998');
		$record->appendField($bib_field);
		$bib_field->appendSubfield(new File_MARC_Subfield('f', 'd'));

		return $record;
	}
	
	/**
	 * Modified records query 
	 */
	
	protected function getModifiedRecordData($date, $limit = null, $offset = 0)
	{
		$sql = trim("
			SELECT
				record_num, record_last_updated_gmt, deletion_date_gmt
			FROM
				sierra_view.record_metadata 
			WHERE
				record_type_code = 'b' AND
				campus_code = '' AND 
				record_last_updated_gmt > :modified_date
			ORDER BY
				record_last_updated_gmt DESC NULLS LAST 
		");
		
		if ( $limit != null )
		{
			$sql .= " LIMIT $limit, $offset";
		}
		
		return $this->getResults($sql, array(':modified_date' => $date));
	}

	/**
	 * Modified records count query
	 */
		
	protected function getModifiedCount($date)
	{
		$sql = trim("
			SELECT
				count(record_num) AS total
			FROM
				sierra_view.record_metadata 
			WHERE
				record_type_code = 'b' AND
				campus_code = '' AND 
				record_last_updated_gmt > :modified_date
		");
		
		$results = $this->getResults($sql, array(':modified_date' => $date));
		
		return (int) $results[0]['total'];
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
		$statement = $this->pdo->prepare($sql);
	
		if ( ! $statement->execute($params) )
		{
			throw new Exception('Could not execute query');
		}
	
		return $statement->fetchAll();
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
}
