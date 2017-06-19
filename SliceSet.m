classdef SliceSet < handle
    
    properties
        BrainImagesObj
        Slices
        ImageNum
        SegmentParams
        BoundaryPts
        SliceArr
        Seed
    end
    
    properties (Dependent = true, SetAccess = private)
        SliceNum
    end
    
    methods
        function ss = SliceSet(BrainImagesObj)
            ss.BrainImagesObj = BrainImagesObj;
            ss.BrainImagesObj.LoadAll;
            ss.ImageNum = BrainImagesObj.GroupNum;
            
            if strcmp(ss.BrainImagesObj.ImportMode,'slide')
                
                % Set initial segmentation parameters
                for i = 1:ss.ImageNum
                    SegmentParams{i}.Threshold = 35;
                    SegmentParams{i}.MinSize = 5000;
                    SegmentParams{i}.Buffer = 10;
                end
                ss.SegmentParams = SegmentParams;

                % Automatically segment all slides based on the intiial
                % parameters
                for i = 1:ss.ImageNum
                    ss.AutoSegmentSlide(i);
                end
            end
        end
        
        function img = ReadImage(ss, SliceID, downsample, ch)
            if strcmp(ch,'import')
                ch = ss.BrainImagesObj.ImportChannels{ss.Slices{SliceID}.FileGroupID};
            end
            % Calculate position for this downsampling rate
            pos = ss.Slices{SliceID}.Position;
            switch ss.BrainImagesObj.ReadMode
                case 'SCN'
                    pos = pos*(ss.BrainImagesObj.Downsample/downsample);
%                     try
                        [~,~,img] = ReadSCN(ss.BrainImagesObj.FileGroups{ss.Slices{SliceID}.FileGroupID,1},ch,floor(log2(downsample)+1),pos);
%                     catch
%                         img = zeros(pos(4),pos(3));
%                     end
                case 'across'
                    pos = pos*ss.BrainImagesObj.Downsample;
                    fin = ss.BrainImagesObj.FileGroups{ss.Slices{SliceID}.FileGroupID,find(strcmp(ss.BrainImagesObj.ChInFile(ss.Slices{SliceID}.FileGroupID,:),ch))};
                    img = imread(fin,'PixelRegion',{[pos(2) downsample pos(2)+pos(4)-1], [pos(1) downsample pos(1)+pos(3)-1]},'Index',ss.Slices{SliceID}.ImgIndex);
                case 'multipage'
                    pos = pos*ss.BrainImagesObj.Downsample;
                    img = imread(ss.BrainImagesObj.FileGroups{ss.Slices{SliceID}.FileGroupID,1},'PixelRegion',{[pos(2) downsample pos(2)+pos(4)-1], [pos(1) downsample pos(1)+pos(3)-1]},'Index',str2num(strrep(ch,'ch','')));
                case 'single'
                    pos = pos*ss.BrainImagesObj.Downsample;
                    img = imread(ss.BrainImagesObj.FileGroups{ss.Slices{SliceID}.FileGroupID,1},'PixelRegion',{[pos(2) downsample pos(2)+pos(4)-1], [pos(1) downsample pos(1)+pos(3)-1]},'Index',ss.Slices{SliceID}.ImgIndex);
                case 'RGB'
                    pos = pos*ss.BrainImagesObj.Downsample;
                    img = imread(ss.BrainImagesObj.FileGroups{ss.Slices{SliceID}.FileGroupID,1},'PixelRegion',{[pos(2) downsample pos(2)+pos(4)-1], [pos(1) downsample pos(1)+pos(3)-1]},'Index',ss.Slices{SliceID}.ImgIndex);
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
        
        function t = GetTransforms(ss)
            for i = 1:ss.SliceNum
                t(i) = ss.Slices{i}.Transform;
            end
        end
        
        function SetTransforms(ss,t)
            for i = 1:ss.SliceNum
                ss.Slices{i}.Transform = t(i);
            end
        end
        
        function SerialRigid(ss,optimizer,metric)
            % Copy slices in case process is canceled
            slicecopy = GetTransforms(ss);
            w = warning('error','images:regmex:registrationOutBoundsTermination');     % Trap warnings with try-catch
            k = 1;
            canceled = 0;
            failed = [];
            hWait = waitbar(k/ss.SliceNum,'Registering Images','CreateCancelBtn',@CancelCalc);
            %set(hWait,'Name','Registering Images','WindowStyle','modal');
            tic;
            if ss.Seed ~= ss.SliceNum
                for i=ss.Seed+1:ss.SliceNum
                    if k==1
                        waitbar(k/ss.SliceNum,hWait);
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    else
                        waitbar(k/ss.SliceNum,hWait,sprintf(['Estimated time remaining: ' num2str(datestr(toc/(k-1)*(ss.SliceNum-k+1)/86400,'HH:MM:SS'))]));
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    end
                    if canceled
                        break
                    end
                    try
                        ss.Slices{i}.Rigid(ss.Slices{i-1}.TransImg,optimizer,metric);
                    catch
                        failed(end+1) = i;
                    end
                    k = k+1;
                end
            end
            if ss.Seed ~= 1 && ~canceled
                for i=ss.Seed-1:-1:1
                    if k==1
                        waitbar(k/ss.SliceNum,hWait);
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    else
                        waitbar(k/ss.SliceNum,hWait,sprintf(['Estimated time remaining: ' num2str(datestr(toc/(k-1)*(ss.SliceNum-k+1)/86400,'HH:MM:SS'))]));
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    end
                    if canceled
                        break
                    end
                    try
                        ss.Slices{i}.Rigid(ss.Slices{i+1}.TransImg,optimizer,metric);
                    catch
                        failed(end+1) = i;
                    end
                    k = k+1;
                end
            end
            if canceled
                ss.SetTransforms(slicecopy);
            elseif ~isempty(failed)
                if length(failed)==1
                    msgbox(['Failed to register slice ' num2str(failed) '.'],'Error','error');
                else
                    msgbox(['Failed to register the following slices: ' num2str(failed(1:end-1),'%i, ') 'and ' num2str(failed(end)) '.'],'Error','error');
                end
            end
            function CancelCalc(source,eventdata)
                canceled=1;
            end
            delete(hWait);
            warning(w);     % Restore previous warning state
        end
        
        function SerialSiftFlow(ss,SiftParams)
                        % Copy slices in case process is canceled
            slicecopy = GetTransforms(ss);
            k = 1;
            canceled = 0;
            failed = [];
            hWait = waitbar(k/ss.SliceNum,'Registering Images','CreateCancelBtn',@CancelCalc);
            set(hWait,'Name','Registering Images','WindowStyle','modal');
            tic;
            if ss.Seed ~= ss.SliceNum
                for i=ss.Seed+1:ss.SliceNum
                    if k==1
                        waitbar(k/ss.SliceNum,hWait);
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    else
                        waitbar(k/ss.SliceNum,hWait,sprintf(['Estimated time remaining: ' num2str(datestr(toc/(k-1)*(ss.SliceNum-k+1)/86400,'HH:MM:SS'))]));
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    end
                    if canceled
                        break
                    end
                    try
                        ss.Slices{i}.SiftFlow(ss.Slices{i-1}.TransImg,SiftParams);
                    catch
                        failed(end+1) = i;
                    end
                    k = k+1;
                end
            end
            if ss.Seed ~= 1 && ~canceled
                for i=ss.Seed-1:-1:1
                    if k==1
                        waitbar(k/ss.SliceNum,hWait);
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    else
                        waitbar(k/ss.SliceNum,hWait,sprintf(['Estimated time remaining: ' num2str(datestr(toc/(k-1)*(ss.SliceNum-k+1)/86400,'HH:MM:SS'))]));
                        set(hWait,'Name',['Registering slice ' num2str(k) ' of ' num2str(ss.SliceNum)]);
                    end
                    if canceled
                        break
                    end
                    try
                        ss.Slices{i}.SiftFlow(ss.Slices{i+1}.TransImg,SiftParams);
                    catch
                        failed(end+1) = i;
                    end
                    k = k+1;
                end
            end
            if canceled
                ss.SetTransforms(slicecopy);
            elseif ~isempty(failed)
                if length(failed)==1
                    msgbox(['Failed to register slice ' num2str(failed) '.'],'Error','error');
                else
                    msgbox(['Failed to register the following slices: ' num2str(failed(1:end-1),'%i, ') 'and ' num2str(failed(end)) '.'],'Error','error');
                end
            end
            function CancelCalc(source,eventdata)
                canceled=1;
            end
            delete(hWait);

        end
        
        function SetupTransformParams(ss,SiftParams)
            % Figure out if any heights or widths are defined
            defined = 0;
            i = 1;
            while i<= ss.SliceNum && ~defined
                if ~isempty(ss.Slices{i}.Width)
                    defined = 1;
                end
                i = i+1;
            end
            if defined
                % Apply same height and width to undefined slices that are in
                % defined slices
                width = ss.Slices{i}.Width;
                height = ss.Slices{i}.Height;
                for i = 1:ss.SliceNum
                    if isempty(ss.Slices{i}.Width)
                        ss.Slices{i}.Width = width;
                        ss.Slices{i}.Height = height;
                    end
                end
            else
                % Calculate starting width and height as the largest image +
                % 20%
                for i = 1:ss.SliceNum
                    width(i) = size(ss.Slices{i}.Image,2);
                    height(i) = size(ss.Slices{i}.Image,1);
                end
                width=round(max(width)*1.2);
                height=round(max(height)*1.2);
                
                % Make width and height odd to ensure they have an exact
                % center
                if mod(width,2) == 0
                    width = width-1;
                end
                if mod(height,2) == 0
                    height = height-1;
                end
                
                for i = 1:ss.SliceNum
                    ss.Slices{i}.Width = width;
                    ss.Slices{i}.Height = height;
                end
            end
            
            % Setup warping and affine transforms for anything that's
            % undefined
            defaulttransform.Affine = [1 0 0; 0 1 0; 0 0 1];
            defaulttransform.Affine2 = [1 0 0; 0 1 0; 0 0 1];
            defaulttransform.vx = zeros(height-SiftParams.patchsize+2,width-SiftParams.patchsize+2);
            defaulttransform.vy = zeros(height-SiftParams.patchsize+2,width-SiftParams.patchsize+2);
            for i = 1:ss.SliceNum
                if isempty(ss.Slices{i}.Transform)
                    ss.Slices{i}.Transform = defaulttransform;
                end
            end
        end
        
        function ReorderSliceArray(ss)
            % Sort order of ss.Slices based on values in ss.Slices{x}.Order
            % Copy orders into vector to sort
            for i = 1:ss.SliceNum
                vec(i) = ss.Slices{i}.Order;
            end
            
            % Sort vector
            [~,vec] = sort(vec);
            
            % Copy objects into new array based on new order
            for i = 1:ss.SliceNum
                SliceCopy{i} = ss.Slices{vec(i)};
            end
            
            % Copy to SliceSet object
            ss.Slices = SliceCopy;
        end
        
        function SortSlices(ss)
            order = 1;
            
            for i = 1:ss.ImageNum
                % Get id's for all slices in this image
                SliceID = 0;
                for j = 1:ss.SliceNum
                    if ss.Slices{j}.FileGroupID == i
                        if SliceID == 0
                            SliceID(1) = j;
                        else
                            SliceID(end+1) = j;
                        end
                    end
                end
                
                if SliceID(1) ~= 0
                    % Sort into columns based on boundary points
                    sortedbp = sort(ss.BoundaryPts{i});
                    col = cell(length(sortedbp)-1,1);
                    coly = cell(length(sortedbp)-1,1);
                    for j = 1:length(SliceID)
                        colnum = 2;
                        while colnum < length(sortedbp) && ss.Slices{SliceID(j)}.OrderAxCenter(1) >= sortedbp(colnum)
                            colnum = colnum+1;
                        end
                        colnum = colnum-1;
                        if isempty(col{colnum})
                            col{colnum}(1) = SliceID(j);
                            coly{colnum}(1) = ss.Slices{SliceID(j)}.OrderAxCenter(2);
                        else
                            col{colnum}(end+1) = SliceID(j);
                            coly{colnum}(end+1) = ss.Slices{SliceID(j)}.OrderAxCenter(2);
                        end
                    end
                    
                    if ss.SliceArr(i) <= 4
                        colorder = 1:length(col);
                    else
                        colorder = length(col):-1:1;
                    end
                    % For sliceorder, 1=up, 0=down
                    if ss.SliceArr(i)==1 || ss.SliceArr(i)==5
                        sliceorder = ones(length(colorder),1);
                    elseif ss.SliceArr(i)==2 || ss.SliceArr(i)==6
                        sliceorder = zeros(length(colorder),1);
                    elseif ss.SliceArr(i)==3 || ss.SliceArr(i)==8
                        sliceorder = ones(length(colorder),1);
                        if length(sliceorder)>1
                            sliceorder(2:2:length(sliceorder)) = 0;
                        end
                    elseif ss.SliceArr(i)==4 || ss.SliceArr(i)==7
                        sliceorder = zeros(length(colorder),1);
                        if length(sliceorder)>1
                            sliceorder(2:2:length(sliceorder)) = 1;
                        end
                    end
                    
                    % Sort each column along y dimension
                    l = 1;
                    for j = colorder
                        [~,ind] = sort(coly{j});
                        col{j} = col{j}(ind);
                        if sliceorder(l)
                            k = 1:length(col{j});
                        else
                            k = length(col{j}):-1:1;
                        end
                        for k = k
                            ss.Slices{col{j}(k)}.Order = order;
                            order = order+1;
                        end
                        l = l+1;
                    end
                end
            end
        end
        
        function ss = set.SliceArr(ss,SliceArr)
            ss.SliceArr = SliceArr;
            ss.SortSlices;
        end
        
        function ss = set.BoundaryPts(ss,BoundaryPts)
            ss.BoundaryPts = BoundaryPts;
            if ~isempty(ss.SliceArr)
                ss.SortSlices;
            end
        end
        
        function LoadSliceImages(ss)
            for i = 1:ss.SliceNum
                pos = ss.Slices{i}.Position;
                ss.Slices{i}.Image = ss.BrainImagesObj.Image{ss.Slices{i}.FileGroupID}(pos(2):pos(2)+pos(4)-1,pos(1):pos(1)+pos(3)-1);
            end
        end
        
        function AddSlice(ss,Position,FileGroupID)
            if ~isempty(ss.Slices)
                ss.Slices{end+1} = SingleSlice(Position,FileGroupID);
            else
                ss.Slices{1} = SingleSlice(Position,FileGroupID);
            end
        end
        
        function DeleteSliceByHandle(ss, h)
            i = 1;
            while i <= ss.SliceNum
                if ss.Slices{i}.Handle == h
                    ss.DeleteSlice(i);
                end
                i = i+1;
            end
        end
        
        function DeleteSlice(ss, SliceID)
            % Reduce order number for all slices with order numbers greater
            % than the slice being deleted
            if ~isempty(ss.Slices{SliceID}.Order)
                for i = 1:ss.SliceNum
                    if ss.Slices{i}.Order > ss.Slices{SliceID}.Order
                        ss.Slices{i}.Order = ss.Slices{i}.Order-1;
                    end
                end
            end
            ss.Slices(SliceID) = [];
        end
        
        function DeleteAllInSlide(ss, ImageID)
            i = 1;
            while i <= ss.SliceNum
                if ss.Slices{i}.FileGroupID == ImageID
                    ss.DeleteSlice(i);
                else
                    i = i+1;
                end
            end
        end
        
        function SliceNum = get.SliceNum(ss)
            if ~isempty(ss.Slices)
                SliceNum = length(ss.Slices);
            else
                SliceNum = 0;
            end
        end
        
        function ss = set.SegmentParams(ss,SegmentParams)
            
            % Find which slides had SegmentParams changed
            SlideID = 0;
            i = 0;
            while i<length(ss.SegmentParams)
                i = i+1;
                if (ss.SegmentParams{i}.Threshold ~= SegmentParams{i}.Threshold || ss.SegmentParams{i}.MinSize ~= SegmentParams{i}.MinSize || ss.SegmentParams{i}.Buffer ~= SegmentParams{i}.Buffer)
                    if SlideID==0
                        SlideID = i;
                    elseif sum(i==SlideID)==0
                        SlideID(end+1) = i;
                    end
                end
            end

            % Transfer the changes to the object
            ss.SegmentParams = SegmentParams;

            % Re-autosegment
            if SlideID ~= 0
                for i = 1:length(SlideID)
                    ss.AutoSegmentSlide(SlideID(i));
                end
            end
        end
        
        function AutoSegmentSlide(ss, ImageID)
            % Delete all previous slices for this slide
            ss.DeleteAllInSlide(ImageID);

            img = ss.BrainImagesObj.Image{ImageID};
            
            % Ensure that full 0-255 range is represented in img for im2bw
            img(1,1) = 0;
            img(1,2) = 255;

            % Create binary image based on threshold from 0 to 255
            bwimg = im2bw(img/255, ss.SegmentParams{ImageID}.Threshold/255);

            % Fill holes in thresholded image
            bwimg = imfill(bwimg,'holes');

            % Remove all objects from the binary image with areas smaller than
            % minobjsize pixels
            bwimg = bwareaopen(bwimg,ss.SegmentParams{ImageID}.MinSize);

            % Segment the image based on connected regions
            bwimg = bwlabel(bwimg);

            % Get the bounding boxes for the identified regions
            bounds = regionprops(bwimg,'BoundingBox');

            width = size(img,2);
            height = size(img,1);
            for i = 1:length(bounds)

                % Initiate variables containing initial bounding boxes
                x1 = floor(bounds(i).BoundingBox(1));
                y1 = floor(bounds(i).BoundingBox(2));
                x2 = x1+bounds(i).BoundingBox(3);
                y2 = y1+bounds(i).BoundingBox(4);

                % Calculate bounding boxes that have been expanded by 'buffer'
                % pixels in both dimensions on both sides
                x1 = x1-ss.SegmentParams{ImageID}.Buffer;
                y1 = y1-ss.SegmentParams{ImageID}.Buffer;
                x2 = x2+ss.SegmentParams{ImageID}.Buffer;
                y2 = y2+ss.SegmentParams{ImageID}.Buffer;

                % Correct bounding boxes that are out of range of the image size
                if x1 < 1
                    x1 = 1;
                end
                if y1 < 1
                    y1 = 1;
                end
                if x2 > width
                    x2 = width;
                end
                if y2 > height
                    y2 = height;
                end

                % Create slice objects
                ss.AddSlice([x1 y1 x2-x1+1 y2-y1+1],ImageID);
            end
        end
        
        
    end
    
end

