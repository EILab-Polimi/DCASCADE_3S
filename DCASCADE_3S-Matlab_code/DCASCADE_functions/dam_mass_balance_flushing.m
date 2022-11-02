function [release_t, ResVolume_post, Q_t , dam_flushing_post ] = dam_mass_balance_flushing(DamDatabase_active, ORparameters_active, Network,  ResVolume_pre, Q_t, Q_input_estimates, date_timestep, FSL_ResVolume_t,  dam_flushing_pre, WL_target_t, flushing_yes)
%DAM_MASS_BALANCE defines the dam reservoir volume and the release given
%the operating rule of the dam baseed on the inflow and volume at t-1. 

%% define dam order for the loop

%to determine the discharge for all reaches, i have to
%process the dams located upstream first

NH = Network.NH;
dam_order = NH(logical(sum(NH == [DamDatabase_active.Node_ID]',1)));

%% define operating rule

release_t = zeros(size(ResVolume_pre));
ResVolume_post = zeros(size(ResVolume_pre));
dam_flushing_post = zeros(size(dam_flushing_pre));

%for each dam
for d=1:length(DamDatabase_active)
    
    %extract values for the dam
    dam_pos = find([DamDatabase_active.Node_ID]==dam_order(d)); %position of the selected dam in DamDatabase

    % input discharge at time t
    Q_input = sum(Q_t(DamDatabase_active(dam_pos).reach_UP));
    
    %if the reservoir volume exceed the FLS after the input, i define a
    %minimum release to avoid activating the spillways. Else, the minimum
    %release is defined by the dam feature min_discharge
    if ResVolume_pre(dam_pos) + Q_input *(24*60*60)/1E6 > FSL_ResVolume_t(dam_pos)
        minrelease =  max((ResVolume_pre(dam_pos) - FSL_ResVolume_t(dam_pos))*1E6/(24*60*60) + Q_input,DamDatabase_active(dam_pos).min_discharge);
    else
        minrelease = DamDatabase_active(dam_pos).min_discharge;
    end

    % define discharge possible from the hydropower outlets give the
    % reservoir level
    hp_maxrelease = Reservoir_LSWConversion(ResVolume_pre(dam_pos) , DamDatabase_active(dam_pos).WL_table, 3, 4);
    %hp_maxrelease = Reservoir_LSWConversion( max( ResVolume_pre(dam_pos) + Q_input *(24*60*60)/1E6, FSL_ResVolume_t ) , DamDatabase_active(dam_pos).WL_table, 3, 4);
    
    %define maximum release to avoid going to negative storage
    maxrelease = min( ResVolume_pre(dam_pos)*1E6/(24*60*60) + Q_input , hp_maxrelease);
    
    % if there is no lag between US1 and LSS2II flushing operation, I start
    % the operation on the LSS2II immediately when US1 start flushing
    if d==2 && dam_flushing_post(1,1)==-1 && dam_flushing_pre(2,1)>=0 && ORparameters_active(2).Fl_param.fllag == 0
        flushing_yes(dam_pos) = 1;
    end
    
    %define in which flushing phase the reservoir is, and which release it
    %has if flushing is happening
    [release_t(dam_pos) , minrelease, dam_flushing_post(dam_pos,:) ] = flushing_relase(DamDatabase_active(dam_pos), ORparameters_active(dam_pos), dam_flushing_pre(dam_pos,:) ,...
        date_timestep , ResVolume_pre(dam_pos) , Q_input , Q_input_estimates(dam_pos) , hp_maxrelease, minrelease, flushing_yes(dam_pos));


    % if release_t == -1, the reservoir is either in normal operations or in refill and pause stages
    if release_t(dam_pos) == -1 % operations continue as normal even during refill and pause stages

        %if the reservoir volume exceed the FLS after the input and the maximum
        %possible release, the spillways are always activated and the release
        %is obtained as the difference between the incoming discharge and the
        %remaining volume left in the reservoir
        if ResVolume_pre(dam_pos) + ( Q_input - hp_maxrelease) *(24*60*60)/1E6 > FSL_ResVolume_t(dam_pos)
            release_t(dam_pos) = Q_input - ( FSL_ResVolume_t(dam_pos) - ResVolume_pre(dam_pos))/(24*60*60)*1E6;
        elseif ResVolume_pre(dam_pos) + ( Q_input - minrelease)*(24*60*60)/1E6  < 0 % if the reservoir is empty, do not release anything
            release_t(dam_pos) =  Q_input;    
        else

        ResVol_target = Reservoir_LSWConversion(WL_target_t(dam_pos) , DamDatabase_active(dam_pos).WL_table, 1, 3);  %Reservoir volume associated to the target WL
        Q_predict = Q_input_estimates(dam_pos); % prediction of input discharge, needed to define the release;
        opt_release = max(0 , ResVolume_pre(dam_pos) + Q_predict*(24*60*60)/1E6 - ResVol_target)*1E6/(24*60*60); %optimal release to meet the target
        release_t(dam_pos) = min( maxrelease , max(minrelease,opt_release )); %actual release given the upper and lower release limits

        end %end of the spillway if
    
    end %end of the flushing if
    
    %calculate hydrological changes downstream dams
    [Q_t] = dam_discharge_correction(dam_pos, DamDatabase_active , Network, release_t(dam_pos) , Q_t );

    %Volume at the end of the daily timestep is the difference
    %between incoming and released volume;
    ResVolume_post(dam_pos) = max(ResVolume_pre(dam_pos) + (Q_input - release_t(dam_pos))*(24*60*60)/1E6,0);
    
end


end

