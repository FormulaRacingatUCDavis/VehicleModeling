clc; clear; close all;

%% Simple Vehicle Model (PE Generation Senior Design LTS 2021)
ScriptPath = which( 'LTSTestVehicle.m' );
RepoPath = ScriptPath(1:strfind( which( 'LTSTestVehicle.m' ), 'Vehicle-Modeling' )-2);

addpath( genpath(RepoPath) );

%% Parameters
%%% Inertia
Vehicle.Inertia.Mass     = 275;   % Total Mass               [kg]
Vehicle.Inertia.Yaw      = 130;   % Total Yaw Inertia        [kg-m^2]
Vehicle.Inertia.PerFront = 0.47;  % Percent Front Mass       [%]
Vehicle.Inertia.Spin     = 0.148; % Wheel Spin Inertia       [kg-m^2]
Vehicle.Inertia.CoG(3)   = 0.250; % Center of Gravity Height [m]

%%% Suspension
Vehicle.Suspension(1).Kinematics.Wheelbase = 1.575; % Wheelbase   [m]
Vehicle.Suspension(1).Kinematics.Track     = 1.220; % Track Width [m]

Vehicle.Suspension(1).Kinematics.RackDisp = linspace(-34, 34, 21) / 1000; % Rack Displacement [mm -> m]
Vehicle.Suspension(1).Kinematics.Steer    = ...
    Vehicle.Suspension(1).Kinematics.RackDisp .* 28*1000/34; % Steer Angle [deg]

Vehicle.Suspension(1).PerLLT = 0.55; % Percent Front Lateral Load Transfer [%]

%%% Controls - Steering
Vehicle.Steering.CFactor = 87.9; % Steering Rack C-Factor [mm/rev]

%%% Controls - Braking
Vehicle.Braking.PedalRatio    = 4.3;                     % Brake Pedal Ratio             [ ]
Vehicle.Braking.PerBalanceBar = 0.50;                    % Percent Front Balance Bar     [%]
Vehicle.Braking.BoreDiameter  = [0.59; 0.8125] * 0.0254; % Master Cylinder Bore Diameter [in -> m]
Vehicle.Braking.PadArea       = [2.9; 1.45] * 0.0254^2;  % Brake Pad Area                [in^2 -> m^2]
Vehicle.Braking.PadFriction   = 0.55;                    % Brake Pad Friction            [ ]

%%% Tire
Vehicle.Tire = load('Hoosier_R25B_16x75-10x7.mat');
Vehicle.Tire = Vehicle.Tire.Tire;

Vehicle.Tire.Pacejka.L.mu.x = 2/3;
Vehicle.Tire.Pacejka.L.mu.y = 2/3;

%%% Powertrain
Vehicle.Powertrain.DriveRatio = 3.5; % Final Drive Ratio [ ]
Vehicle.Powertrain.TorqueMap = MotorTorqueMap(); % Torque Map [N-m]

%%% Aerodynamics
Vehicle.Aero.AirDensity =  1.225; % Air Density                 [kg/m^3]
Vehicle.Aero.DragCoeff  =  0.65 ; % Drag Coefficient            [ ]
Vehicle.Aero.LiftCoeff  = -1.90 ; % Lift Coefficient            [ ]
Vehicle.Aero.RefArea    =  0.958; % Aerodynamic Reference Area  [m^2]
Vehicle.Aero.CoP(1)     =  0.52 ; % Center of Pressure Location [%]notep

%% Operating Conditions
Response.Steer    = linspace( 0, 120, 13 );
Response.BodySlip = linspace(-8,   8, 17 );
Response.Speed    = 
Response.LongAcc  = 

%% State Function
function Out = StateFunction( x, Vehicle, State, i,j,k,l, Mode )
    %%% Powertrain & Brakes
    [BrakingTorque, LinePressure] = SimplifiedBrakingModel( PedalForce, ...
        PedalRatio, BalanceBar  , BoreDiameter, ...
        PadArea   , PadFriction , RotorRadius );

    %%% Tires
    [InputTorque, SpinAcc] = WheelSpeed( SpinRate, DriveTorque, ...
        BrakeTorque, RollingResist, TractiveForce, EffRadius, Inertia, Damping );

    [SlipAngle, SlipRatio, TireVel] = SlipEstimation( ...
        LongVel, LatVel, YawVel, TirePos, Steer, SpinRate, EffRadius);

    [Fx, Fy, Mz, Mx, My] = ContactPatchLoads( Tire, ...
        SlipAngle, SlipRatio, ...
        NormalLoad, Pressure, Inclination, Velocity, ...
        Idx, Model );

    %%% Aerodynamics
    [Drag, Downforce] = SimplifiedAeroLoads( LongVel, ...
        AirDensity, RefArea, DragCoeff, LiftCoeff );

    %%% Chassis & Suspension
    [LongAcc, LatAcc, YawAcc, LongAccTot, LatAccTot] = ...
        FullTrack3DOFAccelerations( TFx, TFy, TMz, AFx, AFy, AMz, ... 
            Wheelbase, TrackWidth, Steer, ...                         
            Mass, YawInertia, CoG, ...                                
            LongVel, LatVel, YawVel );                                

    [NormalLoad] = SimplifiedWeightTransfer( LongAccTot, LatAccTot, ...
            Wheelbase, TrackWidth, Mass, CoG, Downforce, CoP, PerLLT );

end

%% Local Functions
%%% Motor Torque Map
function TorqueMap = MotorTorqueMap()
    TorqueMap.Omega    = linspace(0,7000,50); % Motor Speed [rpm]
    TorqueMap.Throttle = linspace(0,1   ,10); % Throttle    [ ]
    
    [TorqueMap.Omega, TorqueMap.Throttle] = meshgrid( TorqueMap.Omega, TorqueMap.Throttle );
    
    Torque0 = 155;
    Omega0  = 3200;
    OmegaF  = 6000;
    
    TorqueClipping = @(Omega) Torque0 - Torque0 ./ (2*(OmegaF-Omega0)) .* ...
        (Omega - Omega0);
    
    TorqueMap.Torque = TorqueMap.Throttle .* 155;
    TorqueMap.Torque( TorqueMap.Torque > TorqueClipping(TorqueMap.Omega) ) = ...
        TorqueClipping( TorqueMap.Omega( TorqueMap.Torque > TorqueClipping(TorqueMap.Omega) ) );
    
    TorqueMap.Omega = TorqueMap.Omega .* 2*pi/60;
end

%%% Simplified Powertrain
function DriveTorque = SimplifiedPowertrain( Throttle, 
    WheelSpeed, 