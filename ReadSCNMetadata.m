function [ meta ] = ReadSCNMetadata( fn )
    
    % Check existence of file
    if (exist(fn,'file') == 0)

        % Check if '.scn' was ommitted from filename
        if (isempty(strfind(fn,'.scn')))
            fn = [fn '.scn'];
        end
        
        % Throw error if file still cannot be found
        if (exist(fn,'file') == 0)
            error(['The file ' fn ' could not be found.']);
        end
    end
    
    % Get ImageDescription data from file
    try
        SCNTiff = Tiff(fn,'r');
        idXML = SCNTiff.getTag('ImageDescription');
        SCNTiff.close();
    catch
        error(['Unable to load ' fn '. File may not be a valid SCN file.']);
    end
    
    % Do basic test to make sure requested file is an SCN file by checking
    % to see if the Leica specification URL is in the ImageDescription tag
     if (isempty(strfind(idXML,'http://www.leica-microsystems.com/scn/2010/10/01')))
        error(['The file ' fn ' is not a valid SCN file.']);
     end 

    % Create xml object from string
    import org.xml.sax.InputSource
    import javax.xml.parsers.*
    import java.io.*
    iS = InputSource();
    iS.setCharacterStream( StringReader(idXML) );
    p = xmlread(iS);

    % Read in ImageDescription data from written file
    meta = xml2struct(p);

end

