function [ ChannelRGB ChannelNames img ] = ReadSCN( fn, channel, downsample, varargin )
% ReadSCN: Read fluorescence images from Leica SCN file
%
% Usage: [ChannelRGB ChannelNames ImageData] = ...
%    ReadSCN(filename, channel, Downsampling Rate, subregion);
%
% Output variables:
%   -ChannelRGB: An n-by-3 array, where n is the number of fluorescence
%    channels in the file. Each row contains three values corresponding to
%    the RGB value (0 to 255) specified for each channel in the file.
%   -ChannelNames: An n-element cell array of strings, where n is the
%    number of fluorescence channels in the file. Each element contains a
%    string with the name of the channel (e.g. 'Aqua' or 'Spectrum Green'.)
%   -ImageData: If a single channel is requested, this is an h-by-w array
%    specifying the intensity values (0 to 255) of each pixel in an h-by-w
%    image. If multiple channels are requested, this is an h-by-w-by-n
%    array, where n is the number of channels. If 'all' is specificed for
%    the channel input variable and the file contains only one channel,
%    then the resulting ImageData will by an h-by-w-by-1 array.
%
% Input variables:
%   -filename: Filename or path of the SCN file to read.
%   -channel: An integer value specifying which fluorescence channel to
%    read. If it is instead the string 'all', then the function will read
%    and return all fluorescence channels in the file. If it is the string
%    'counterstain', the function will read and return only the channel
%    that is indicated as the counterstain. It may also be a string naming
%    the channel to load (e.g. 'Aqua' or 'Spectrum Green').
%   -downsample: The downsampling rate. If this is 1, then the full
%    resolution image is returned. If this is n, then an image downsampled
%    by 2^(n-1) in both dimensions will be returned. If n exceeds the number of
%    downsampled images in the SCN file, then the function will increase
%    downsampling by reading only a fraction of the pixels from the most
%    highly downsampled image in the SCN file.
%   -(optional) subregion: a 4-element row vector of the form
%    [x y width height] specifying a subregion of the image to load. x and
%    y are the (x,y) coordinate of the upper-left corner of the sub-region,
%    where the upper-left corner of the full image is (1,1). width and
%    heigh are the width and heigh of the sub-region, in pixels. The
%    specified coordinates correspond to the image at the requested
%    downsapling rate.
%
% Limitations:
%   -Discards brightfield scan passes
%   -Cannot handle SCN files containing fluorescence scan passes that are
%    not all identical to each other (i.e. with different magnifications or
%    channels)
%   -Cannot handle SCN files with z-stacks
%
% Casey Guenthner, Stanford University (cjg@stanford.edu)

% Get metadata for the file
meta = ReadSCNMetadata(fn);

% Find the total number of series in the file
NumSeries = length(meta.scn.collection.image);

% Loop through all the series and identify which ones are for fluorescence
% scan passes
for i = 1:NumSeries
    if strcmp(meta.scn.collection.image{i}.scanSettings.illuminationSettings.illuminationSource.Text, 'fluorescence')
        if ~exist('FluorSeries')
            FluorSeries(1) = i;
        else
            FluorSeries(length(FluorSeries)+1) = i;
        end
        
    end
end

% Make sure SCN file contains a fluorescence series, and, if it doesn't,
% throw an error
assert(exist('FluorSeries','var')==1, ...
    'SCN file does not contain any fluorescence series.');

% Loop through all fluorescence scan passes and collect their attributes
NumFluorSeries = length(FluorSeries);
Mag = zeros(NumFluorSeries,1);
ChannelNum = zeros(NumFluorSeries,1);
CounterstainChannel = zeros(NumFluorSeries,1);
DownsampleNum = zeros(NumFluorSeries,1);
offsetX = zeros(NumFluorSeries,1);
offsetY = zeros(NumFluorSeries,1);
sizeX = zeros(NumFluorSeries,1);
sizeY = zeros(NumFluorSeries,1);
ChannelNames = cell(NumFluorSeries,1);
ChannelRGB = cell(NumFluorSeries,1);

for i = 1:NumFluorSeries
    Ind = FluorSeries(i);
    Mag(i) = str2num(meta.scn.collection.image{Ind}.scanSettings.objectiveSettings.objective.Text);
    ChannelNum(i) = length(meta.scn.collection.image{Ind}.scanSettings.channelSettings.channel);
    ChannelNames{i} = cell(ChannelNum(i),1);
    ChannelRGB{i} = zeros(ChannelNum(i),3);
    for j = 1:ChannelNum(i)
        if sum(strcmp('counterstain',fieldnames(meta.scn.collection.image{Ind}.scanSettings.channelSettings.channel{j}.Attributes)))
            CounterstainChannel(i) = j;
        end
        ChannelNames{i}{j} = meta.scn.collection.image{Ind}.scanSettings.channelSettings.channel{j}.Attributes.name;
        RGB = meta.scn.collection.image{Ind}.scanSettings.channelSettings.channel{j}.Attributes.rgb;
        ChannelRGB{i}(j,1:3) = [hex2dec(RGB(2:3)) hex2dec(RGB(4:5)) hex2dec(RGB(6:7))];
    end
    DownsampleNum(i) = length(meta.scn.collection.image{Ind}.pixels.dimension)/ChannelNum(i);
    offsetX(i) = str2num(meta.scn.collection.image{Ind}.view.Attributes.offsetX);
    offsetY(i) = str2num(meta.scn.collection.image{Ind}.view.Attributes.offsetY);
    sizeX(i) = str2num(meta.scn.collection.image{Ind}.view.Attributes.sizeX);
    sizeY(i) = str2num(meta.scn.collection.image{Ind}.view.Attributes.sizeY);
end

% Get model of instrument used to collect images (to distinguish old-style
% from new-style SCN files)
model = meta.scn.collection.image{1}.device.Attributes.model;

% Check file attributes and throw errors/warnings if necessary
% Check that all series have the same number of channels
assert(all(ChannelNum(:)==ChannelNum(1)),...
    'Image file contains series with different numbers of channels.');

% If there's more than one series, then make sure the channel information
% for all series is the same
if NumFluorSeries > 1
    % Check that the channel names for all series are equivalent
    assert(isequal(ChannelNames{:}),...
        'Image file contains series with different channel names.');
    % Check that the RGB values for the channels of all series are equivalent
    assert(isequal(ChannelRGB{:}),...
        'Image file contains series with different channel RGB values.');
    % Check that the magnification for all series is equivalent
    assert(all(Mag(:)==Mag(1)),...
        'Image file contains series with different magnifications.');
end

% Figure out what channels to load
LoadCh = zeros(NumFluorSeries,1);
if isnumeric(channel)
    % If channel is an integer, then check that the requested channel falls
    % within the appropriate bounds
    assert(all(channel<=ChannelNum(:)) & (channel>0), ...
        'Requested channel does not exist in the indicated file.');
    
    % Load the same channel number for all series
    LoadCh(1:NumFluorSeries) = channel;
else
    % Loop through all the channels to see if any match the requested
    % channel
    for j = 1:ChannelNum(1)
        if strcmp(ChannelNames{1}(j),channel)
            % If channel channel name j = the requested channel, then set
            % all channels to load to this value
            LoadCh(1:NumFluorSeries) = j;
        end
    end    
    
    if LoadCh(1) == 0
        % If the requested channel didn't match any of the channel names,
        % then check if it is 'all' or 'counterstain'
        if strcmp(channel,'counterstain')
            LoadCh = CounterstainChannel;
        elseif ~strcmp(channel,'all')
            % Out of options--channel value must be wrong
            % If channel is 'all' then LoadCh stays as zeros
            error([channel ' is not a valid input value for channel.']);
        end
    end
end


% Check requested downsampling rates and re-set if necessary; set
% BoostDownsample variable to determine how much additional downsampling is
% needed to apply to imread; maximum downsampling from SCN file is equal to
% the smallest downsampling present for each series
MaxDownsample = min(DownsampleNum);
if downsample > MaxDownsample
    BoostDownsample = (downsample-MaxDownsample)*2;
    downsample = MaxDownsample;
else
    BoostDownsample = 1;
end

% Determine which UIDs to use to obtain maximal downsampling
pixelsX = zeros(NumFluorSeries,1);
pixelsY = zeros(NumFluorSeries,1);
UID = cell(NumFluorSeries,1);
for i = 1:NumFluorSeries
    Ind = FluorSeries(i);
    if strcmp(model, 'Versa')
        % New-style SCN file in which series are sorted by channel and then
        % by downsampling
        pixelsX(i) = str2num(meta.scn.collection.image{Ind}.pixels.dimension{downsample}.Attributes.sizeX);
        pixelsY(i) = str2num(meta.scn.collection.image{Ind}.pixels.dimension{downsample}.Attributes.sizeY);
    else
        % Old-style SCN file in which series are sorted by downsampling and
        % then by channel
        pixelsX(i) = str2num(meta.scn.collection.image{Ind}.pixels.dimension{downsample*ChannelNum(i)}.Attributes.sizeX);
        pixelsY(i) = str2num(meta.scn.collection.image{Ind}.pixels.dimension{downsample*ChannelNum(i)}.Attributes.sizeY);
    end
    
    UID{i} = zeros(ChannelNum(i),1);
    for j = 1:ChannelNum(i)
        if strcmp(model, 'Versa')    
            UID{i}(j) = str2num(meta.scn.collection.image{Ind}.pixels.dimension{downsample+DownsampleNum(i)*(j-1)}.Attributes.ifd); 
        else
            UID{i}(j) = str2num(meta.scn.collection.image{Ind}.pixels.dimension{(downsample-1)*ChannelNum(i)+j}.Attributes.ifd);
        end
    end
end
            
% Stitch series
% Calculate offset-to-pixel conversion
PixRatio = sizeX(1)/pixelsX(1);

% Convert offsets to pixels
offsetX = offsetX/PixRatio;
offsetY = offsetY/PixRatio;

% Re-position (minX, minY) at (1,1)
offsetX = floor(offsetX-min(offsetX)+1);
offsetY = floor(offsetY-min(offsetY)+1);

% Calculate maximum positions on both axes
maxX = max(offsetX+pixelsX);
maxY = max(offsetY+pixelsY);

% Load image data
if length(varargin) == 1
    % i.e. if a position to load is specified
    % Calculate pixels included in requested position, considering the fact
    % that the final image must be flipped horizontally
    SubMaxX = maxX-BoostDownsample*varargin{1}(1)+1;
    SubMinX = SubMaxX-BoostDownsample*varargin{1}(3)+1;
    SubMinY = BoostDownsample*varargin{1}(2);
    SubMaxY = SubMinY+BoostDownsample*varargin{1}(4)-1;

    % Calculate the boundaries of the series within the larger image
    SeriesMaxX = offsetX+pixelsX-1;
    SeriesMaxY = offsetY+pixelsY-1;
    
    % Store pixels within each region to include and the corresponding
    % positions in the resulting image
    IncludedRegions = cell(NumFluorSeries,1);
    PixelPos = cell(NumFluorSeries,1);
    
    % Determine which series contain image data overlapping the requested
    % region
    for i = 1:NumFluorSeries
        
        % Define series and image positions for the x-axis
        if (SubMaxX >= offsetX(i)) & (SeriesMaxX(i) >= SubMaxX)...
                & (SubMinX < offsetX(i))
            % right part of image partially overlaps left part of series
            IncludedRegions{i}(1) = 1;
            IncludedRegions{i}(2) = SubMaxX-offsetX(i)+1;
            PixelPos{i}(1) = offsetX(i)-SubMinX+1;
            PixelPos{i}(2) = varargin{1}(3)*BoostDownsample;
        elseif (SubMaxX >= offsetX(i)) & (SeriesMaxX(i) >= SubMaxX) ...
                & (SubMinX >= offsetX(i)) & (SubMinX <= SeriesMaxX(i))
            % image is included entirely within the series
            IncludedRegions{i}(1) = SubMinX-offsetX(i)+1;
            IncludedRegions{i}(2) = SubMaxX-offsetX(i)+1;
            PixelPos{i}(1) = 1;
            PixelPos{i}(2) = varargin{1}(3)*BoostDownsample;                    
        elseif (SubMinX >= offsetX(i)) & (SubMinX <= SeriesMaxX(i)) ...
                & (SubMaxX > SeriesMaxX(i))
            % left part of image partially overlaps with series
            IncludedRegions{i}(1) = SubMinX-offsetX(i)+1;
            IncludedRegions{i}(2) = pixelsX(i);
            PixelPos{i}(1) = 1;
            PixelPos{i}(2) = SeriesMaxX(i)-SubMinX+1;
        elseif (SubMinX < offsetX(i)) & (SubMaxX > SeriesMaxX(i))
            % image spans entire series but has some extent beyond the
            % series in both directions
            IncludedRegions{i}(1) = 1;
            IncludedRegions{i}(2) = pixelsX(i);
            PixelPos{i}(1) = offsetX(i)-SubMinX+1;
            PixelPos{i}(2) = SeriesMaxX(i)-SubMinX+1;
        end    
        
        % Now do the same for the y-axis
        if (SubMaxY >= offsetY(i)) & (SeriesMaxY(i) >= SubMaxY)...
                & (SubMinY < offsetY(i))
            % bottom part of image partially overlaps top part of series
            IncludedRegions{i}(3) = 1;
            IncludedRegions{i}(4) = SubMaxY-offsetY(i)+1;
            PixelPos{i}(3) = offsetY(i)-SubMinY+1;
            PixelPos{i}(4) = varargin{1}(4)*BoostDownsample;
        elseif (SubMaxY >= offsetY(i)) & (SeriesMaxY(i) >= SubMaxY) ...
                & (SubMinY >= offsetY(i)) & (SubMinY <= SeriesMaxY(i))
            % image is included entirely within the series
            IncludedRegions{i}(3) = SubMinY-offsetY(i)+1;
            IncludedRegions{i}(4) = SubMaxY-offsetY(i)+1;
            PixelPos{i}(3) = 1;
            PixelPos{i}(4) = varargin{1}(4)*BoostDownsample;      
        elseif (SubMinY >= offsetY(i)) & (SubMinY <= SeriesMaxY(i)) ...
                & (SubMaxY > SeriesMaxY(i))
            % top part of image partially overlaps with series
            IncludedRegions{i}(3) = SubMinY-offsetY(i)+1;
            IncludedRegions{i}(4) = pixelsY(i);
            PixelPos{i}(3) = 1;
            PixelPos{i}(4) = SeriesMaxY(i)-SubMinY+1;
        elseif (SubMinY < offsetY(i)) & (SubMaxY > SeriesMaxY(i))
            % image spans entire series but has some extent beyond the
            % series in both directions
            IncludedRegions{i}(3) = 1;
            IncludedRegions{i}(4) = pixelsY(i);
            PixelPos{i}(3) = offsetY(i)-SubMinY+1;
            PixelPos{i}(4) =  SeriesMaxY(i)-SubMinY+1;        
        end    
    end
    
    % Allocate variable to store image information
    if strcmp(channel,'all')
        % Add a third dimension to the image array to hold multiple
        % channels
        img = zeros(varargin{1}(4), varargin{1}(3), max(ChannelNum));
    else
        % One channel requires only a two dimensional array
        img = zeros(varargin{1}(4), varargin{1}(3));
    end
    
    % Load pixel data into image array
    for i = 1:NumFluorSeries
        if length(find(PixelPos{i})) == 4
            PixelPos{i} = floor(PixelPos{i}/BoostDownsample)+1;   
            if LoadCh(1) == 0
                % Load all of the channels
                for j = 1:ChannelNum(i)
                    imgreg = imread(fn,'Index',UID{i}(j)+1,'PixelRegion', ...
                        {[IncludedRegions{i}(3) BoostDownsample IncludedRegions{i}(4)] ...
                        [IncludedRegions{i}(1) BoostDownsample IncludedRegions{i}(2)]});
                    img(PixelPos{i}(3):(PixelPos{i}(3)+size(imgreg,1)-1),...
                        PixelPos{i}(1):(PixelPos{i}(1)+size(imgreg,2)-1),j) = imgreg;
                end
            else
                % Load a channel specified by LoadCh
                imgreg = imread(fn,'Index',UID{i}(LoadCh(i))+1,'PixelRegion', ...
                    {[IncludedRegions{i}(3) BoostDownsample IncludedRegions{i}(4)] ...
                    [IncludedRegions{i}(1) BoostDownsample IncludedRegions{i}(2)]});
                img(PixelPos{i}(3):(PixelPos{i}(3)+size(imgreg,1)-1),...
                    PixelPos{i}(1):(PixelPos{i}(1)+size(imgreg,2)-1)) = imgreg;
            end

        end
    end
else
    % Calculate boundaries in the full image of each of the series
    % For each series, SeriesPos = [XMin XMax YMin YMax]
    SeriesPos = zeros(NumFluorSeries,4);
    for i = 1:NumFluorSeries
        SeriesPos(i,:) = [offsetX(i) offsetX(i)+pixelsX(i)-1 offsetY(i) offsetY(i)+pixelsY(i)-1];
    end
    
    if BoostDownsample == 1
        % Load image with no extra downsampling
        % Generate image array
        if strcmp(channel,'all')
            % Three-dimensional array needed to hold multiple channels
            img = zeros(floor(maxY), floor(maxX), max(ChannelNum));
        else
             img = zeros(floor(maxY), floor(maxX));
        end
        
        % Load image data into image array
        for i = 1:NumFluorSeries           
            if LoadCh(1) == 0
                % Load all of the channels
                for j = 1:ChannelNum(i)
                    img(SeriesPos(i,3):SeriesPos(i,4), SeriesPos(i,1):SeriesPos(i,2),j) = ...
                        imread(fn,'Index',UID{i}(j)+1);   
                end
            else
                % Load a channel specified by the channel number
                img(SeriesPos(i,3):SeriesPos(i,4), SeriesPos(i,1):SeriesPos(i,2)) = ...
                    imread(fn,'Index',UID{i}(LoadCh(i))+1);
            end
        end
    else
        % Load image with additional downsampling
        SeriesPos = floor(SeriesPos/BoostDownsample)+1;

        % Generate image array
        if strcmp(channel,'all')
            img = zeros(floor(maxY/BoostDownsample)+1, floor(maxX/BoostDownsample)+1, ChannelNum);
        else
            img = zeros(floor(maxY/BoostDownsample)+1, floor(maxX/BoostDownsample)+1);
        end
        
        for i = 1:NumFluorSeries
            if LoadCh(1) == 0
                % Load all of the channels
                for j = 1:ChannelNum(i)
                    imgreg = imread(fn,'Index',UID{i}(j)+1,...
                        'PixelRegion',{[1 BoostDownsample pixelsY(i)] [1 BoostDownsample pixelsX(i)]});
                    img(SeriesPos(i,3):(SeriesPos(i,3)+size(imgreg,1)-1),...
                        SeriesPos(i,1):(SeriesPos(i,1)+size(imgreg,2)-1),j) = imgreg;
                end
            else
                % Load a channel specified by the channel number
                % First read in the image
                imgreg = imread(fn,'Index',UID{i}(LoadCh(i))+1,...
                    'PixelRegion',{[1 BoostDownsample pixelsY(i)] [1 BoostDownsample pixelsX(i)]});

                % And then copy the image into the overall image array based on
                % the size of the read image; this is necessary because the
                % additional downsampling makes the exact size of the read
                % image slightly imprecise (due to rounding, etc.)
                img(SeriesPos(i,3):(SeriesPos(i,3)+size(imgreg,1)-1),...
                    SeriesPos(i,1):(SeriesPos(i,1)+size(imgreg,2)-1)) = imgreg;
            end
        end
    end
end

% Flip image horizontally to display in correct orientation
if strcmp(channel,'all')
    for i = 1:size(img,3)
        img(:,:,i) = fliplr(img(:,:,i));
    end
else
    img = fliplr(img);
end

% Set ChannelNames and ChannelRGB variables for output (assumes
% ChannelNames and RGB values are the same for all series, so just output
% the list for the first series
ChannelNames = ChannelNames{1};
ChannelRGB = ChannelRGB{1};

end
