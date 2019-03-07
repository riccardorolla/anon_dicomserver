$conf = Read-Properties $PSScriptRoot\anon_dicomserver.properties
$studies = import-csv  $PSScriptRoot\anon_dicomserver.csv -delimiter ";"

$conf.hash ={ 
	param([String] $String,$HashName = "MD5") 
		$StringBuilder = New-Object System.Text.StringBuilder 
		[System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))|%{ 
		[Void]$StringBuilder.Append($_.ToString("x2")) 
		} 
		$StringBuilder.ToString() 
}

start-dicomserver -Port $conf.port -AET $conf.aet  -Environment $conf  -onCStoreRequest {
	param($request,$file,$association,$env)
		$attribute = read-dicom -DicomFile $file
		$hashcode = (Invoke-Command $env.hash -ArgumentList $attribute.PatientID,"MD5")  + $env.salt
		$anom_patientID = $hashcode
		$anom_PatientName = $hashcode.substring(0,16) + "^" + $hashcode.substring(16,16)
		$anon_birthdate = $attribute.PatientBirthDate.AddDays($env.diff_date)
		$anon_studydate = $attribute.StudyDate.addDays($env.diff_date)
		$anom_StudyID = (Invoke-Command $env.hash -ArgumentList $attribute.StudyInstanceUID,"MD5")  + $env.salt
		
		$anonimous_file = 	edit-dicom -Tag "0010,0010" -Value $anom_PatientName -DicomFile $file 	|  
							edit-dicom -Tag "0010,0020" -Value $anom_patientID 						|  
							edit-dicom -Tag "0008,0050" -Value $anom_StudyID 						|
							edit-dicom -Tag "0020,0010" -Value $anom_StudyID 						|
							edit-dicom -Tag "0010,0030" -Value $anom_birthdate 						|
							edit-dicom -Tag "0008,0020" -Value $anom_studydate 						|
							edit-dicom -Tag "0008,0080" -Value "anon_InstitutionName" 				|
							edit_dicom -Tag "0008,0082" -Value "anon_InstitutionAddress"		   
		send-dicom -AET $env.aet -SopClassProvider $env.destination -DicomFile  $anonimous_file
		[Dicom.Network.DicomStatus]::success
}



foreach ($study in $studies) {
Write-Host $study.PatientID
				search-dicom  -Study  -SopClassProvider $conf.source  -AET $conf.aet  -PatientId $study.PatientId -StartDateTime (get-date $study.data_esame_densita) -EndDateTime  (get-date $study.data_esame_densita).AddDays(1)  | 
				move-dicom -Study -SopClassProvider  $conf.source  -AET $conf.aet -moveTo  $conf.aet -StudyInstanceUID {$_.StudyInstanceUID}
				}
 
 