function batch_postproc
% WARNING!!!!
% This function combines the functions listed below. Functions are nested
% here to share the variables (e.g. no copy of the axonlist in the
% sub-functions).
% This results in much lower memory consumption (factor 20)
% This was a dirty quick fix, someone should try to use the functions
% separated and prevent duplication of variables in memory.
%
% - as_StitchfromTileConfig_axonlist
% - as_stats_downsample
% - as_display_label
TileConfigFile='TileConfiguration_matlab.txt';
%% LAUNCH THIS SCRIPT IN MOSAIC FOLDER
% if ~exist(TileConfigFile,'file')
    png=sct_tools_ls('../*.PNG'); png = png(cellfun(@isempty,strfind(png,'review')));
    N=sscanf(png{1},'%dx%d_%d.PNG'); % mosaic dimensions
    as_stitch_CorrectOutliers('TileConfiguration.registered.txt',N);
    drawnow;
% end


%% READ
% Read axonlist
metric = 'axonEquivDiameter';
try
    png=sct_tools_ls('../*.PNG'); png = png(cellfun(@isempty,strfind(png,'review')));
    N=sscanf(png{1},'%dx%d_%d.PNG'); % mosaic dimensions
    PixelSize = N(3)/1000;
catch
    try
        load(sct_tools_ls('axonlist_full_image.mat',1,0,2,1,1),'PixelSize');
    catch
        load(sct_tools_ls('axonlist_full_image.mat',1,0,2,1,3),'PixelSize');
    end
end

as_StitchfromTileConfig_axonlist_lowmemory(TileConfigFile);
tmp;axonlist;
%save('axonlist_full_image_nodata.mat', 'axonlist', 'matrixsize', 'PixelSize','-v7.3')


%% SAVE STATS
cd ..
mkdir maps
cd maps
for resolution = [50 100 200]; % 50 �m downsampling
as_stats_downsample_lowmemory(PixelSize,resolution);
imagesc(stats_downsample(:,:,7))
% save_nii assumes LPI orientation. So: Rows=Left-Right. Columns =
% Posterior-Interior
% Rotate matrix to follow this convention
% Left size on the Left? or RL?
png=sct_tools_ls('../*.PNG'); png = png(cellfun(@isempty,strfind(png,'review')));
if  ~isempty(png) && ~isempty(strfind(png{1},'_RL')), RL=1; else RL = 0; end

stats_downsample = permute(stats_downsample,[2 1 4 3]);
if RL
    stats_downsample = stats_downsample(end:-1:1,end:-1:1,:,:);
else
    stats_downsample =  stats_downsample(:,end:-1:1,:,:);
end

mkdir(['stats_' num2str(resolution) 'um'])
save_nii(make_nii(stats_downsample,[resolution/1000 resolution/1000 1]),['stats_' num2str(resolution) 'um/stats_downsample4D.nii']);

for istat=1:length(sFields)
    save_nii(make_nii(stats_downsample(:,:,:,istat),[resolution/1000 resolution/1000 1]),['stats_' num2str(resolution) 'um/' num2str(istat) '_' sFields{istat} '.nii']);
end
end
% %% Save Images
clear axonlist
cd ../mosaic
maxval=8*scale; %8�m diameter; ceil(prctile(axonseg(axonseg>0),99));
reducefactor=max(1,ceil(max(matrixsize)/25000));

as_StitchfromTileConfig_lowmemory(TileConfigFile,~rm);
cd ../maps
img = imadjust(img);

RGB = ind2rgb8(axonseg(1:reducefactor:size(axonseg,1),1:reducefactor:size(axonseg,2),:),hot(maxval));
I=0.5*RGB(1:min(end,size(img,1)),1:min(end,size(img,2)),:)+0.5*repmat(img(1:min(end,size(RGB,1)),1:min(end,size(RGB,2))),[1 1 3]);
colorBar = hot(size(I,1))*255; colorBar = colorBar(end:-1:1,:);
imwrite(cat(2,I,permute(repmat(colorBar,[1 1 max(1,round(0.025*size(I,2)))]),[1 3 2])),[metric '_(axon)_0_' num2str(double(maxval)/scale) unit '.png'])

RGB = ind2rgb8(myelinseg(1:reducefactor:size(myelinseg,1),1:reducefactor:size(myelinseg,2),:),hot(maxval));
I=0.5*RGB(1:min(end,size(img,1)),1:min(end,size(img,2)),:)+0.5*repmat(img(1:min(end,size(RGB,1)),1:min(end,size(RGB,2))),[1 1 3]);
imwrite(cat(2,I,permute(repmat(colorBar,[1 1 max(1,round(0.025*size(I,2)))]),[1 3 2])),[metric '_(myelin)_0_' num2str(double(maxval)/scale) unit '.png'])

    function as_StitchfromTileConfig_axonlist_lowmemory(fname)
        % Panorama = as_StitchfromTileConfig
        % reads TileConfiguration.registered.txt, generated by FIJI Grid stitch,
        % and stitch images to create matrix Panorama
        %
        % display Panorama using:
        % AS_DISPLAY_LARGEIMAGE(Panorama);
        
        if ~exist('fname','var'), fname='TileConfiguration.registered.txt'; end
        [fname,ColPos,RowPos] = as_stitch_LoadTileConfiguration(fname);
        
        Msize = size(imread(fname{1}));
        
        
        if exist('x1_Segmentation','dir')
            fname = cellfun(@(ff) ['x' strrep(ff,'.png','_Segmentation')],fname,'UniformOutput',false);
        elseif exist(strrep(fname{10},'.png','_Segmentation'),'dir')
            fname = cellfun(@(ff) strrep(ff,'.png','_Segmentation'),fname,'UniformOutput',false);
        else
            fname = cellfun(@(ff) genvarname(strrep(ff,'.png','_Segmentation')),fname,'UniformOutput',false);
        end
        
        rm = cell2mat(cellfun(@(ff) ~exist([ff filesep 'axonlist_full_image.mat'],'file'),fname,'UniformOutput',false));
        fname(rm)=[]; ColPos(rm)=[]; RowPos(rm)=[];
        
        RowPos = round(RowPos-min(RowPos)+1);
        ColPos = round(ColPos-min(ColPos)+1);
        matrixsize = [(max(RowPos) + Msize(1)) (max(ColPos) + Msize(2))];
        axonseg=zeros(matrixsize,'uint8');
        myelinseg=zeros(matrixsize,'uint8');
        
        for iff = 1:length(fname)
            disp([num2str(iff) '/' num2str(length(fname))])
            tmp = load([fname{iff} filesep 'axonlist_full_image.mat'],'axonlist');
            tmp.axonlist = tmp.axonlist;
            if ~isempty(tmp.axonlist)
                tmp.axonlist([tmp.axonlist.conflict]>0.5)=[];
                tmp.axonlist([tmp.axonlist.axonEquivDiameter]>15)=[];
                if ~isempty(tmp.axonlist)
                    as_axonlist_changeorigin([RowPos(iff) ColPos(iff)],N,iff,ColPos, RowPos);
                    as_display_label(metric);
                    if ~exist('axonlist','var'), axonlist = rmfield(tmp.axonlist,'data');
                    else
                        axonlist = cat(2,axonlist,rmfield(tmp.axonlist,'data'));
                    end
                end
            end
            
        end
    end



    function as_axonlist_changeorigin(neworigin,N,iff, ColPos, RowPos)
        % EXAMPLE : as_axonlist_changeorigin(listcell{1,1}.seg,size(listcell{1,1}.img), [100 100])
        
        
        to_remove_bottom=zeros(N(1),N(2));
        to_remove_bottom(1:size(to_remove_bottom,1)-1,:)=1;
        to_remove_bottom=to_remove_bottom(:);

        to_remove_right=zeros(N(1),N(2));
        to_remove_right(:,1:size(to_remove_right,2)-1)=1;
        to_remove_right=to_remove_right(:);
        
        
        if ~isempty(tmp.axonlist(1).Centroid)
            % change centroids
            centroids=cat(1,tmp.axonlist.Centroid);
            
            if to_remove_bottom(iff)==1
                b=find(centroids(:,1)>round(5632-(5632-(RowPos(iff+1)-RowPos(iff)))));
            end
            
             if to_remove_right(iff)==1
                c=find(centroids(:,2)>round(8192-(8192-(ColPos(iff+N(1))-ColPos(iff)))));
            end           
  
            centroids(:,1)=centroids(:,1)+neworigin(1);
            centroids(:,2)=centroids(:,2)+neworigin(2);
            centroidscell=mat2cell(centroids,ones(size(centroids,1),1));
            [tmp.axonlist.Centroid]=deal(centroidscell{:});
            
            if to_remove_right(iff)==1 && to_remove_bottom(iff)==1
            
                d=vertcat(b,c);
                d=unique(d);

                tmp.axonlist(d)=[];
            
            elseif to_remove_right(iff)==1 && to_remove_bottom(iff)==0
                
                tmp.axonlist(c)=[];

            elseif to_remove_right(iff)==0 && to_remove_bottom(iff)==1
                
                tmp.axonlist(b)=[];
                
            end
            
            % change data
            if isfield(tmp.axonlist,'data')
                data=cat(1,tmp.axonlist.data);
                data(:,1)=data(:,1)+neworigin(1); data(:,2)=data(:,2)+neworigin(2);
                datacell=mat2cell(data,cat(1,tmp.axonlist.myelinAera));
                [tmp.axonlist.data]=deal(datacell{:});            
            end
        end
    end


    function as_display_label(metric)
        %[im_out,AxStats]=AS_DISPLAY_LABEL(axonlist, matrixsize, metric);
        %[im_out,AxStats]=AS_DISPLAY_LABEL(axonlist, matrixsize, metric, displaytype, writeimg?);
        %
        % --------------------------------------------------------------------------------
        % INPUTS:
        %   metric {'gRatio' | 'axonEquivDiameter' | 'myelinThickness' | 'axon number' | 'random'}
        %   Units: gRatio in percents / axonEquivDiameter in  um x 10 /
        %   myelinThickness in um x 10
        %   displaytype {'axon' | 'myelin'} = 'myelin'
        %   writeimg {img,0} = 0
        %
        % --------------------------------------------------------------------------------
        % EXAMPLE:
        %   bw_axonseg=as_display_label(axonlist,size(img),'axonEquivDiameter','axon');
        %   RGB = ind2rgb8(bw_axonseg,hot(150)); % create rgb mask [0 15um].
        %   as_display_LargeImage(RGB+repmat(img,[1 1 3])); % DISPLAY!
        
        % Get number of axons contained in the axon list
        Naxon=length(tmp.axonlist)
        
        for i=Naxon:-1:1
            %if ~mod(i,1000), disp(i); end
            if size(tmp.axonlist(i).data,1)>5
                index=round(tmp.axonlist(i).data);
                indm=sub2ind(matrixsize,min(matrixsize(1),max(1,index(:,1))),min(matrixsize(2),max(1,index(:,2))));
                index=as_myelin2axon(max(1,index));
                inda=sub2ind(matrixsize,min(matrixsize(1),max(1,index(:,1))),min(matrixsize(2),max(1,index(:,2))));
                
                
                if ~isempty(tmp.axonlist(i))
                    switch metric
                        case 'gRatio'
                            scale = 100; unit = '';
                            value=uint8(tmp.axonlist(i).gRatio(1)*scale);
                        case 'axonEquivDiameter'
                            scale = 10; unit = 'um';
                            value=uint8(tmp.axonlist(i).axonEquivDiameter(1)*scale);
                        case 'myelinThickness'
                            scale = 10; unit = 'um';
                            value=uint8(tmp.axonlist(i).myelinThickness(1)*scale);
                        case 'axon number'
                            scale = 1; unit = '';
                            value=i;
                        case 'random'
                            scale = 1; unit = '';
                            value=uint8(rand*254+1);
                        otherwise
                            if ~exist('scale','var')
                                values = max([tmp.axonlist.(metric)]);
                                scale = 10^floor(log10(255/values));
                                unit = '';
                            end
                            
                            if ~isempty(tmp.axonlist(i).(metric))
                                value=tmp.axonlist(i).(metric)*scale;
                            end
                    end
                    axonseg(inda) = value;
                    myelinseg(indm) = value;
                end
            end
        end
    end



    function as_stats_downsample_lowmemory(PixelSize,resolution)
        %[stats_downsample, statsname]=as_stats_downsample(axonlist,matrixsize(�m),PixelSize(�m),resolution)
        %
        % IN:   -axonlist (output structure from AxonSeg, containing axon & myelin
        %       info
        %       -matrixsize (size x and y of image in axonlist)
        %       -PixelSize (size of one pixel, output of AxonSeg, comes with
        %       axonlist)
        %       -resolution (um value of downsampled image, i.e. you can take the
        %       resolution of your MRI image, can take different resolutions for x
        %       and y)
        %       -outputstats (true if you want the output stats)
        %
        % Ex: [stats_downsample, sFields, axonlistcell]=as_stats_downsample(axonlist,size(img),0.8,30);
        %
        %--------------------------------------------------------------------------
        
        
        % Calculate nbr of pixels for each sub-region in the downsampled image
        dsx=resolution(1)/(PixelSize);
        dsy=resolution(end)/(PixelSize);
        
        % Get the x & y coordsfor each sub-region
        Xcoords=1:dsx:matrixsize(1);
        Ycoords=1:dsy:matrixsize(2);
        
        % Use the centroids of the axons to determine position of axons
        Centroids=cat(1,axonlist.Centroid);
        
        % get stats fields we're using (axonArea, axonDiam,...)
        sFields=as_stats_fields;
        
        % init. matrix that will contain downsampled values for each stat (3D)
        stats_downsample=zeros([length(Xcoords) length(Ycoords) length(sFields)+11]);
        
        % create cell array with same size as downsample image
        if nargout>2, axonlistcell=cell(length(Xcoords),length(Ycoords)); end
        
        % for each downsample cell, calculate mean stats from axonlist
        for x=1:length(Xcoords)
            for y=1:length(Ycoords)
                
                % identify centroids (axons) that are in the current downsample
                % cell
                inpixel=find(Centroids(:,1)>Xcoords(x) & Centroids(:,1)<Xcoords(min(x+1,end)) & Centroids(:,2)>Ycoords(y) & Centroids(:,2)<Ycoords(min(y+1,end)));
                
                % Remove segmented twice
                SegTwice = as_axonlist_distance_closerthandiameter(axonlist(inpixel),0.5,PixelSize);
                inpixel = inpixel(~SegTwice);
                
                % copy identified centroids in related axonlist cell
                if nargout>2, axonlistcell{x,y}=inpixel; end
                
                % for each stat field, take the mean of the stat for axons in
                % current downsample cell
                for istat=1:length(sFields)
                    stats_downsample(x,y,istat)=median([axonlist(inpixel).(sFields{istat})]);
                end
                
                % One of the stats = nbr of axons in each downsample cell
                stats_downsample(x,y,length(sFields)+1)=length(inpixel);
                
                % Another stat added = std of axon diameter
                tmp=[axonlist(inpixel).axonEquivDiameter];
                stats_downsample(x,y,length(sFields)+2)=std(tmp);
                
                % Another stat added = sum(AxonDiam.^3)./sum(AxonDiam.^2)
                stats_downsample(x,y,length(sFields)+3)=sum(tmp.^3)./sum(tmp.^2);
                
                % If there are axons in downsample cell
                if sum(inpixel)
                    
                    %
                    cellsize=ceil([Xcoords(min(x+1,end))-Xcoords(x), Ycoords(min(y+1,end))-Ycoords(y)]);
                    % Calculate myelin volume fraction = myelin pixels / total
                    % pixels of cell
                    MVF=sum(sum(~~myelinseg(Xcoords(x):Xcoords(min(x+1,end)),Ycoords(y):Ycoords(min(y+1,end)))))/(cellsize(1)*cellsize(2));
                    % Another stat added = MTV in each downsample cell
                    stats_downsample(x,y,length(sFields)+4)=MVF;
                    % AVF
                    AVF = sum(sum(~~axonseg(Xcoords(x):Xcoords(min(x+1,end)),Ycoords(y):Ycoords(min(y+1,end)))))/(cellsize(1)*cellsize(2));
                    stats_downsample(x,y,length(sFields)+5)=AVF;
                    % calculate fr = AVF/(1-MVF) and add it as stat
                    fr=AVF/(1-MVF);
                    stats_downsample(x,y,length(sFields)+6)=fr;
                    % Axon shape
                    Stats = regionprops(axonseg(Xcoords(x):Xcoords(min(x+1,end)),Ycoords(y):Ycoords(min(y+1,end))),{'Solidity','Eccentricity','Orientation','Perimeter','Area'});
                    stats_downsample(x,y,length(sFields)+7) = median([Stats.Solidity]);
                    stats_downsample(x,y,length(sFields)+8) = median([Stats.Eccentricity]);                    
                    stats_downsample(x,y,length(sFields)+9) = median([Stats.Orientation]);  
                    stats_downsample(x,y,length(sFields)+10) = std([Stats.Orientation]);  
                    stats_downsample(x,y,length(sFields)+11) = median(4*pi*[Stats.Area]./[Stats.Perimeter].^2);  
                end
            end
        end
        % set all existing NAN to 0
        stats_downsample(isnan(stats_downsample))=0;
        
        % specify fields for added stats (not in original axonlist)
        sFields{end+1}='Number_axons';
        sFields{end+1}='axonEquivDiameter_std';
        sFields{end+1}='axonEquivDiameter_axonvolumeCorrected';
        sFields{end+1}='MVF';
        sFields{end+1}='AVF';
        sFields{end+1}='fr';
        sFields{end+1}='Solidity';
        sFields{end+1}='Eccentricity';
        sFields{end+1}='Orientation';
        sFields{end+1}='OrientationDispersion';
        sFields{end+1}='Circularity';
    end


    function as_StitchfromTileConfig_lowmemory(fname,index,renamefun)
        % Panorama = as_StitchfromTileConfig
        % reads TileConfiguration.registered.txt, generated by FIJI Grid stitch,
        % and stitch images to create matrix Panorama
        %
        % renamefun  =@(x) ['myelin_segmentation_' x];
        % as_StitchfromTileConfig([],renamefun)
        %
        % display Panorama using:
        % AS_DISPLAY_LARGEIMAGE(Panorama);
        
        if ~exist('fname','var'), fname='TileConfiguration.registered.txt'; end
        
        [fname,ColPos,RowPos] = as_stitch_LoadTileConfiguration(fname);
        if exist('renamefun','var')
            fname = cellfun(renamefun,fname,'UniformOutput',false);
        end
        if exist('index','var') && ~isempty(index)
            [fname,I]=sort_nat(fname);
            ColPos = ColPos(I);
            RowPos = RowPos(I);
            
            fname = fname(index);
            ColPos = ColPos(index);
            RowPos = RowPos(index);
        end
        
        Msize = size(imread(fname{1}));
        RowPosmod = round(RowPos-min(RowPos));
        ColPosmod = round(ColPos-min(ColPos));
        
        [maxRowPos,MRind]=max(RowPosmod); MsizeRow = size(imread(fname{MRind}),1);
        [maxColPos,MRind]=max(ColPosmod); MsizeColPos = size(imread(fname{MRind}),2);
        img = zeros(floor(round(maxRowPos+MsizeRow+1)/reducefactor),floor(round(maxColPos+MsizeColPos+1)/reducefactor),'uint8');
        
        rest_row = mod(RowPosmod,reducefactor);
        rest_col = mod(ColPosmod,reducefactor);
        for ff = 1:length(fname)
            tmp = imread(fname{ff}); dim=size(tmp); if size(tmp,3)==3, tmp = rgb2gray(tmp); end
            tmp = tmp((1+rest_row(ff)):reducefactor:end,(1+rest_col(ff)):reducefactor:end);
            img(ceil((RowPosmod(ff)+1)/reducefactor):(ceil((RowPosmod(ff)+1)/reducefactor)+size(tmp,1)-1),ceil((ColPosmod(ff)+1)/reducefactor):(ceil((ColPosmod(ff)+1)/reducefactor)+size(tmp,2)-1))=im2uint8(tmp);
        end
        %as_display_LargeImage(Panorama);
    end
end