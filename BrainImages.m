classdef BrainImages < handle

    % No channel delimiter specified = channels are within one file or only
    % one channel is given
    % 
    properties
        FullNames
        ImportMode
        Type
        ChannelDelimiter
        SliceDelimiter
        ChannelNames           %Each row contains the channels corresponding to the channels in the files in the same row of FileGroups
        ImportChannels         %Channels the user selected to import for each file group
        Downsample
        Image
        FileGroups = ''             % Columns contain channels, rows contain sections
    end
    
    properties (Dependent = true, SetAccess = private)
        FileGroupNames
        FileNum
        GroupNum
        FileNames
        TableArray
        ChannelList             % List of all channels, collapsed across files
    end
    
    properties (SetAccess = private)
        ChInFile                    % For file groups in which different channels are in different files
        ReadMode
    end
    
    methods
        function brain = BrainImages(fn,ImportMode,varargin)
            % fn will contain a cell array of full filepaths/names for a
            % set of brain image files. First loop through them and extract
            % file name parts


            % Check file properties to make sure they're acceptable
            badfiles = '';
            i = 1;
            while i<=length(fn)
                filetype{i} = 'TIFF';
                bad = 0;
                try
                    info = imfinfo(fn{i});
                    if ~strcmp(info(1).Format,'tif')
                        bad = 1;
                    elseif ~(strcmp(info(1).ColorType,'grayscale') || strcmp(info(1).ColorType,'indexed') || strcmp(info(1).ColorType,'truecolor'))
                        bad = 1;
                        % Could still be an SCN
                        try
                            temp = ReadSCNMetadata(fn{i});
                            bad = 0;
                            filetype{i} = 'SCN';
                        end
                    end
                catch
                    bad = 1;
                end
                if bad
                    if isempty(badfiles)
                        badfiles{1} = fn{i};
                    else
                        badfiles{end+1} = fn{i};
                    end
                    fn(i) = [];
                else
                    i = i+1;
                end
            end

            if sum(strcmp(filetype,filetype{1}))<length(filetype)
                msgbox('All selected files must be of the same type.','Error','error');
                fn = {};
            elseif ~isempty(badfiles)
                msgbox(['The following files are not valid image types:' badfiles],'Error','error');
            end
            
            brain.FullNames = fn;            
            brain.ImportMode = ImportMode;
            brain.Type = filetype{1};

            for i = 1:length(varargin)
                if strcmp(varargin{i},'ChannelDelimiter')
                    brain.ChannelDelimiter = varargin{i+1};
                elseif strcmp(varargin{i},'SliceDelimiter')
                    brain.SliceDelimiter = varargin{i+1};
                end
            end
            brain.SortFiles;
            brain.getChannelNames;
            for i = 1:brain.GroupNum
               ImportChannels{i} = brain.ChannelNames{i}{1};
            end
            brain.ImportChannels = ImportChannels;
        end
        
        function LoadAll(brain)
            % Load preview images for all file groups
            hWait = waitbar(0,'Loading images...');
            for i = 1:brain.GroupNum
                brain.Image{i} = ImportImage(brain,i,'import');
                if strcmp(brain.ReadMode,'SCN')
                    brain.Image{i} = permute(brain.Image{i},[2 1]);
                end
                waitbar(i/brain.GroupNum);
            end
            close(hWait);
        end
        
        function img = ImportImage(brain, GroupID, ch, varargin)        % varargin is index to load if file's a stack
            if ~isempty(varargin)
                index = varargin{1};
            else
                index = 1;
            end
            if strcmp(ch,'import')
                ch = brain.ImportChannels{GroupID};
            end
            switch brain.ReadMode
                case 'SCN'
                    if brain.Downsample >= 16 || strcmp('Yes',questdlg('Opening an image preview of a full slide with low downsampling may cause the system to freeze. Are you sure you want to continue?'))
                        [~,~,img] = ReadSCN(brain.FileGroups{GroupID,1},ch,floor(log2(brain.Downsample)+1));
                        img = permute(img,[2 1]);
                    else
                        img = zeros(10,10);
                    end
                case 'across'
                    info = imfinfo(brain.FileGroups{GroupID,find(strcmp(brain.ChInFile(GroupID,:),ch))});
%                     if strcmp(brain.ImportMode,'stack') && length(info)>1
%                         index = floor(length(info)/2);
%                     else
%                         index = 1;
%                     end
                    img = imread(info(1).Filename,'Info',info,'PixelRegion',{[1 brain.Downsample info(1).Height], [1 brain.Downsample info(1).Width]},'Index',index);
                case 'multipage'
                    info = imfinfo(brain.FileGroups{GroupID,1});
                    img = imread(info(1).Filename,'Info',info,'PixelRegion',{[1 brain.Downsample info(1).Height], [1 brain.Downsample info(1).Width]},'Index',str2num(strrep(ch,'ch','')));
                case 'single'
                    info = imfinfo(brain.FileGroups{GroupID,1});
%                     if strcmp(brain.ImportMode,'stack') && length(info)>1
%                         index = floor(length(info)/2);
%                     else
%                         index = 1;
%                     end
                    img = imread(info(1).Filename,'Info',info,'PixelRegion',{[1 brain.Downsample info(1).Height], [1 brain.Downsample info(1).Width]},'Index',index);
                case 'RGB'
                    info = imfinfo(brain.FileGroups{GroupID,1});
%                     if strcmp(brain.ImportMode,'stack') && length(info)>1
%                         index = floor(length(info)/2);
%                     else
%                         index = 1;
%                     end
                    img = imread(info(1).Filename,'Info',info,'PixelRegion',{[1 brain.Downsample info(1).Height], [1 brain.Downsample info(1).Width]},'Index',index);
                    switch ch
                        case 'Red'
                            img = img(:,:,1);
                        case 'Green'
                            img = img(:,:,2);
                        case 'Blue'
                            img = img(:,:,3);
                    end
            end
            if ~isa(img,'double')
                img = double(img);
            end
        end
        
        function brain = set.ImportMode(brain,ImportMode)
            if ~isempty(brain.ImportMode)
                brain.ImportMode = ImportMode;
                brain.SortFiles;
                brain.getChannelNames;
                for i = 1:brain.GroupNum
                    ImportChannels{i} = brain.ChannelNames{i}{1};
                end
                brain.ImportChannels = ImportChannels;
            else
                brain.ImportMode = ImportMode;
            end
        end
        
        function brain = set.ImportChannels(brain,ImportChannels)
            reset = 1;
            for i = 1:length(ImportChannels)
                if ~sum(strcmp(ImportChannels{i},brain.ChannelNames{i}))==1
                    reset = 0;
                end
            end
            if reset
                brain.ImportChannels = ImportChannels;
            else
                msgbox('The selected channel is not present in the file or file group.','Error','error');
            end
        end
        
        function brain = set.ChannelDelimiter(brain,ChannelDelimiter)
            ChannelDelimiter = strrep(ChannelDelimiter,' ','');
            if ~strcmp(ChannelDelimiter,brain.ChannelDelimiter)
                
                % Make sure delimiter is present in all files
                str = '';
                if ~isempty(ChannelDelimiter)
                    delind = strfind(brain.FileNames,ChannelDelimiter);
                    for i = 1:length(delind)
                        if isempty(delind{i})
                            if isempty(str)
                                str{1} = brain.FileNames{i};
                            else
                                str{end+1} = brain.FileNames{i};
                            end
                        end
                    end
                end
                
                if isempty(str)
                    brain.ChannelDelimiter =  ChannelDelimiter;
                    brain.SortFiles;
                    brain.getChannelNames;
                    for i = 1:brain.GroupNum
                        ImportChannels{i} = brain.ChannelNames{i}{1};
                    end
                    brain.ImportChannels = ImportChannels;
                else
                    msgbox(['The channel delimiter could not be found in the following files:' str],'Error','error');
                end
            end
        end

        function brain = set.SliceDelimiter(brain,SliceDelimiter)
            SliceDelimiter = strrep(SliceDelimiter,' ','');
            if ~strcmp(SliceDelimiter,brain.SliceDelimiter)
                                
                % Make sure delimiter is present in all files
                str = '';
                
                if ~isempty(SliceDelimiter)
                    delind = strfind(brain.FileNames,SliceDelimiter);
                    for i = 1:length(delind)
                        if isempty(delind{i})
                            if isempty(str)
                                str{1} = brain.FileNames{i};
                            else
                                str{end+1} = brain.FileNames{i};
                            end
                        end
                    end
                end
                
                if isempty(str)
                    brain.SliceDelimiter =  SliceDelimiter;
                    brain.SortFiles;
                    brain.getChannelNames;
                    for i = 1:brain.GroupNum
                        ImportChannels{i} = brain.ChannelNames{i}{1};
                    end
                    brain.ImportChannels = ImportChannels;
                else
                    msgbox(['The slice delimiter could not be found in the following files:' str],'Error','error');
                end
            end
        end
        
        function ChannelList = get.ChannelList(brain)
            ChannelList = unique([brain.ChannelNames{:}]);
        end
        
        % Function to construct array to display in table
        function TableArray = get.TableArray(brain)
            for i = 1:brain.GroupNum
                AvailableChannels = brain.ChannelNames{i}{1};
                for j = 2:size(brain.ChannelNames{i},2)
                    AvailableChannels = [AvailableChannels ', ' brain.ChannelNames{i}{j}];
                end
                TableArray(i,:) = {brain.FileGroupNames{i} AvailableChannels brain.ImportChannels{i}};
            end
        end
        
        function FileGroupNames = get.FileGroupNames(brain)
            if ~isempty(brain.ChannelDelimiter)
                % Group name is filename without the channel delimiter
                
                if isempty(brain.SliceDelimiter)
                    % If slice delimiter isn't specified, then truncate before
                    % start of channel delimiter
                    for i = 1:brain.GroupNum
                        [~,startname,~] = fileparts(brain.FileGroups{i,1});
                        FileGroupNames{i} = startname(1:regexp(startname,brain.ChannelDelimiter,'start')-1);
                    end                    
                else
                    % If slice dlimiter is specified, then remove channel
                    % delimiter and channel designation
                    for i = 1:brain.GroupNum
                        [~,startname,~] = fileparts(brain.FileGroups{i,1});
                        if regexp(startname,brain.ChannelDelimiter,'end') > regexp(startname,brain.SliceDelimiter,'end')
                            FileGroupNames{i} = startname(1:regexp(startname,brain.ChannelDelimiter,'start')-1);
                        else
                            chdelstart = regexp(startname,brain.ChannelDelimiter,'start');
                            sdelstart = regexp(startname,brain.SliceDelimiter,'start');
                            FileGroupNames{i} = [startname(1:chdelstart-1) startname(sdelstart:end)];
                        end
                    end
                end

            else
                % Group names are the same as the file name for the one
                % file in the group
                for i = 1:brain.GroupNum
                    [~, FileGroupNames{i}, ~] = fileparts(brain.FileGroups{i}); 
                end
            end
        end
        
        function FileNum = get.FileNum(brain)
            FileNum = length(brain.FullNames);
        end
        
        function FileNames = get.FileNames(brain)
            for i = 1:brain.FileNum
                [~, FileNames{i}, ~] = fileparts(brain.FullNames{i}); 
            end
        end
        
        function GroupNum = get.GroupNum(brain)
            GroupNum = size(brain.FileGroups,1);
        end
        

    end
    
    methods (Access = 'private')
        
        function getChannelNames(brain)
            brain.ChannelNames = cell(1,1);
            brain.ChInFile = cell(1,1);
            if strcmp(brain.Type,'SCN')         % strcmp(brain.ImportMode,'slide') && 
                % Whole-slide SCN files - get channels from SCN
                % metadata
                brain.ReadMode = 'SCN';
                for i = 1:brain.GroupNum
                    [~, brain.ChannelNames{i}, ~] = ReadSCN(brain.FileGroups{i,1},'all',1,[1 1 1 1]);
                    brain.ChannelNames{i} = permute(brain.ChannelNames{i},[2 1]);
                end
            elseif ~isempty(brain.ChannelDelimiter)
                % If channel delimiter is specified, then get channel name
                % from file name
                brain.ReadMode = 'across';
                for i = 1:brain.GroupNum
                   k = 1;
                   for j = 1:size(brain.FileGroups,2)
                        if ~isempty(brain.FileGroups{i,j})
                            [~,str,~] = fileparts(brain.FileGroups{i,j});
                            if isempty(brain.SliceDelimiter) || (regexp(str,brain.ChannelDelimiter,'end') > regexp(str,brain.SliceDelimiter,'end'))
                                % If slice delimiter isn't specified or if slice delimiter comes after channel delimiter, then go from
                                % after channel delimiter to end of filename
                                brain.ChannelNames{i}{k} = str(regexp(str,brain.ChannelDelimiter,'end')+1:end);
                                brain.ChInFile{i,j} = str(regexp(str,brain.ChannelDelimiter,'end')+1:end);
                            else
                                % Channel delimiter comes after slice
                                % delimiter, so go from after channel delimiter
                                % to start of slice delimiter
                                brain.ChannelNames{i}{k} = str(regexp(str,brain.ChannelDelimiter,'end')+1:regexp(str,brain.SliceDelimiter,'start')-1);
                                brain.ChInFile{i,j} = str(regexp(str,brain.ChannelDelimiter,'end')+1:end);
                            end
                            k = k+1;
                        end
                    end
                end
            else
                % Analyze tiff files to get channels
                for i = 1:brain.GroupNum
                    info = imfinfo(brain.FileGroups{i});
                    if ~strcmp(brain.ImportMode,'stack') && size(info,1) > 1
                        % Multi-page TIFF file, consider each page a
                        % separate channel
                        brain.ReadMode = 'multipage';
                        for j = 1:size(info,1)
                            brain.ChannelNames{i}{j} = ['ch' num2str(j)];
                        end
                    elseif strcmp(info(1).ColorType,'grayscale') || strcmp(info(1).ColorType,'indexed')
                        % Single channel in file
                        brain.ReadMode = 'single';
                        brain.ChannelNames{i} = {'ch1'};
                    elseif strcmp(info(1).ColorType,'truecolor')
                        % RGB image - treat R, G, and B as separate
                        % channels for now
                        brain.ReadMode = 'RGB';
                        brain.ChannelNames{i} = {'Red','Green','Blue'};
                    else
                        % Error handling
                    end
                end
            end
            
        end
        
        function SortFiles(brain)
            if ~isempty(brain.SliceDelimiter) && ~isempty(brain.ChannelDelimiter)
                sliceid = cell(brain.FileNum,1);
                channelid = cell(brain.FileNum,1);
                for i = 1:brain.FileNum
                    [sdelstart(i) sdelend(i)] = regexp(brain.FileNames{i},brain.SliceDelimiter);
                    [cdelstart(i) cdelend(i)] = regexp(brain.FileNames{i},brain.ChannelDelimiter);
                    strend(i) = length(brain.FileNames{i});
                    if cdelstart(i) < sdelstart(i)      % channel delimiter comes before slice delimiter
                        channelid{i} = brain.FileNames{i}(cdelend(i)+1:sdelstart(i)-1);
                        sliceid{i} = brain.FileNames{i}(sdelend(i)+1:strend(i));
                    else
                        sliceid{i} = brain.FileNames{i}(sdelend(i)+1:cdelstart(i)-1);
                        channelid{i} = brain.FileNames{i}(cdelend(i)+1:strend(i));
                    end
                end
                UniqueChannels = sort(unique(channelid));
                UniqueSlices = sort(unique(sliceid));
                brain.FileGroups = cell(length(UniqueSlices),length(UniqueChannels));
                for i = 1:length(UniqueSlices)
                    sliceid(strcmp(sliceid,UniqueSlices{i})) = {i};
                end
                for i = 1:length(UniqueChannels)
                    channelid(strcmp(channelid,UniqueChannels{i})) = {i};
                end
                for i = 1:brain.FileNum
                    brain.FileGroups{sliceid{i},channelid{i}} = brain.FullNames{i};
                end
            elseif ~isempty(brain.SliceDelimiter)
                % NEED TO CHECK FOR DUPLICATES
                sliceid = cell(brain.FileNum,1);
                for i = 1:brain.FileNum
                    sdelend(i) = regexp(brain.FileNames{i},brain.SliceDelimiter,'end');
                    strend(i) = length(brain.FileNames{i});
                    sliceid{i} = brain.FileNames{i}(sdelend(i)+1:strend(i));
                end
                UniqueSlices = sort(unique(sliceid));
                brain.FileGroups = cell(length(UniqueSlices),1);
                for i = 1:length(UniqueSlices)
                    sliceid(strcmp(sliceid,UniqueSlices{i})) = {i};
                end
                for i = 1:brain.FileNum
                    brain.FileGroups{sliceid{i},1} = brain.FullNames{i};
                end
            elseif ~isempty(brain.ChannelDelimiter)
                % after sorting channels, need to sort slices by name
                channelid = cell(brain.FileNum,1);
                for i = 1:brain.FileNum
                    cdelend(i) = regexp(brain.FileNames{i},brain.ChannelDelimiter,'end');
                    strend(i) = length(brain.FileNames{i});
                    channelid{i} = brain.FileNames{i}(cdelend(i)+1:strend(i));
                    sliceid{i} = strrep(brain.FileNames{i},channelid{i},'');
                end
                UniqueChannels = sort(unique(channelid));
                UniqueSlices = sort(unique(sliceid));
                brain.FileGroups = cell(length(UniqueSlices),length(UniqueChannels));
                for i = 1:length(UniqueSlices)
                    sliceid(strcmp(sliceid,UniqueSlices{i})) = {i};
                end
                for i = 1:length(UniqueChannels)
                    channelid(strcmp(channelid,UniqueChannels{i})) = {i};
                end
                for i = 1:brain.FileNum
                    brain.FileGroups{sliceid{i},channelid{i}} = brain.FullNames{i};
                end
%                 if strcmp(brain.ImportMode,'stack')
%                     fg = brain.FileGroups;
%                     brain.FileGroups = cell(0,0);
%                     for i = 1:size(fg,1)
%                         info = imfinfo(fg{i,1});
%                         info = length(info);
%                         for j = 1:info
%                             brain.FileGroups(end+1,:) = fg(i,:);
%                         end
%                     end
%                 end
            else
                brain.FileGroups = permute(sort(brain.FullNames),[2 1]); 
            end
        end
    end
    
end

