<?php

namespace Shrew;

/**
 * Sierra access object
 *
 * @author David Walker <dwalker@calstate.edu>
 */

class Sierra
{
	/**
	 * @var \PDO
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
		$this->pdo = new \PDO("pgsql:host=$host;port=$port;dbname=$dbname", $username, $password);
		$this->pdo->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
	}
	
	/**
	 * Fetch results from the database 
	 * 
	 * @param string $sql
	 * @throws Exception
	 * @return array
	 */
	
	protected function getResults($sql)
	{
		$statement = $this->pdo->prepare($sql);
	
		if ( ! $statement->execute() )
		{
			throw new \Exception('Could not execute query');
		}
	
		return $statement->fetchAll();
	}	
	
	/**
	 * Fetch an individual record
	 * 
	 * @param string $id
	 * @return \File_MARC_Record
	 */
	
	public function getBibRecord($id)
	{
		$sql = trim("
		SELECT
			bib_view.id,
			varfield_view.marc_tag,
			varfield_view.marc_ind1,
			varfield_view.marc_ind2,
			varfield_view.field_content,
			varfield_view.varfield_type_code,
			leader_field.*
		FROM
			sierra_view.bib_view,
			sierra_view.varfield_view,
			sierra_view.leader_field
		WHERE
			bib_view.id = varfield_view.record_id AND 
			bib_view.id = leader_field.record_id AND 
			bib_view.record_num = '$id'
		");
		
		$results = $this->getResults($sql);
	
		$record = new \File_MARC_Record();
	
		// leader
		
		$result = $results[0];
		
		// 0000's here get converted to correct lengths by \File_MARC
		
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
		
		foreach ( $results as $id => $result )
		{
			// control field
			
			if ( (int) $result['marc_tag'] < 10 )
			{
				$control_field = new \File_MARC_Control_Field($result['marc_tag'], $result['field_content']);
				$record->appendField($control_field);
			}
			
			// data field
			
			else 
			{
				$data_field = new \File_MARC_Data_Field($result['marc_tag']);
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
					
					$subfield = new \File_MARC_Subfield($code, trim($data));
					$data_field->appendSubfield($subfield);
				}
				
				$record->appendField($data_field);
			}
		}
		
		return $record;
	}
}

