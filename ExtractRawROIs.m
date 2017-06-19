% Get input file
[fn,FilePath,~] = uigetfile({'*.mat' '3D Brain Project File'});
if ischar(fn) && ischar(FilePath)
    fn = strcat(FilePath,fn);
else
    error('Invalid input file.');
end

% Check that required image files exist
dat = load(fn);
brain = dat.brain;
ss = dat.ss;

% Check if image files can be found
FilesMissing = 1;
while FilesMissing
    FileList = [];
    for i = 1:brain.FileNum
        if ~exist(brain.FullNames{i},'file')
            [~,FileList{end+1},ext] = fileparts(brain.FullNames{i});
            FileList{end} = [FileList{end} ext];
        end
    end
    if isempty(FileList)
        FilesMissing = 0;
    else
        if length(FileList)>10
            ans = questdlg(['The following files are associated with this project but could not be found:' {FileList{1:5} '.' '.' '.' FileList{end-4:end}} 'All files belonging to this project must be in the same folder. Would you like to locate them?']);
        else
            ans = questdlg(['The following files are associated with this project but could not be found:' FileList 'All files belonging to this project must be in the same folder. Would you like to locate them?']);
        end
        if strcmp(ans,'Yes')
            % Locate missing files
            newdir = uigetdir;
            for i = 1:brain.FileNum
                [~,filename,ext] = fileparts(brain.FullNames{i});
                filename = [filename ext];
                brain.FullNames{i} = [newdir '\' filename];
            end
            for j = 1:brain.GroupNum
                for k = 1:size(brain.FileGroups,2)
                    if ~isempty(brain.FileGroups{j,k})
                        [~,filename,~] = fileparts(brain.FileGroups{j,k});
                        filename = [filename ext];
                        brain.FileGroups{j,k} = [newdir '\' filename];
                    end
                end
            end
        else
            error('Unable to locate image files.');
        end
    end
end

% Get output file
% Ask user where to save the file
[~,FilePath] = uiputfile({'*.tif' '3D Brain TIF File'});
if ~ischar(FilePath)
    error('Invalid output file.');
end

% Export files
fncounter = zeros(ss.BrainImagesObj.GroupNum,1);
for i = 1:ss.SliceNum
    fncounter(ss.Slices{i}.FileGroupID) = fncounter(ss.Slices{i}.FileGroupID)+1;
    InputFile = ss.BrainImagesObj.FileGroups{ss.Slices{i}.FileGroupID};
    [~,fnoutname,~] = fileparts(InputFile);
    OutputFile = [FilePath '/' fnoutname '_' num2str(fncounter(ss.Slices{i}.FileGroupID)) '.tif'];
    [~,~,img] = ReadSCN(InputFile,'all',1,ss.BrainImagesObj.Downsample*ss.Slices{i}.Position);
    for j = 1:size(img,3)
        imwrite(img(:,:,j)/256,OutputFile,'WriteMode','append');
    end
end