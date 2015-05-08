/**
 * DeviceDetailViewController.m
 * MetaWearApiTest
 *
 * Created by Laura Kassovic on 5/7/15.
 * Copyright 2014 MbientLab Inc. All rights reserved.
 *
 * IMPORTANT: Your use of this Software is limited to those specific rights
 * granted under the terms of a software license agreement between the user who
 * downloaded the software, his/her employer (which must be your employer) and
 * MbientLab Inc, (the "License").  You may not use this Software unless you
 * agree to abide by the terms of the License which can be found at
 * www.mbientlab.com/terms . The License limits your use, and you acknowledge,
 * that the  Software may not be modified, copied or distributed and can be used
 * solely and exclusively in conjunction with a MbientLab Inc, product.  Other
 * than for the foregoing purpose, you may not use, reproduce, copy, prepare
 * derivative works of, modify, distribute, perform, display or sell this
 * Software and/or its documentation for any purpose.
 *
 * YOU FURTHER ACKNOWLEDGE AND AGREE THAT THE SOFTWARE AND DOCUMENTATION ARE
 * PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESS OR IMPLIED,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTY OF MERCHANTABILITY, TITLE,
 * NON-INFRINGEMENT AND FITNESS FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL
 * MBIENTLAB OR ITS LICENSORS BE LIABLE OR OBLIGATED UNDER CONTRACT, NEGLIGENCE,
 * STRICT LIABILITY, CONTRIBUTION, BREACH OF WARRANTY, OR OTHER LEGAL EQUITABLE
 * THEORY ANY DIRECT OR INDIRECT DAMAGES OR EXPENSES INCLUDING BUT NOT LIMITED
 * TO ANY INCIDENTAL, SPECIAL, INDIRECT, PUNITIVE OR CONSEQUENTIAL DAMAGES, LOST
 * PROFITS OR LOST DATA, COST OF PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY,
 * SERVICES, OR ANY CLAIMS BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY
 * DEFENSE THEREOF), OR OTHER SIMILAR COSTS.
 *
 * Should you have any questions regarding your right to use this Software,
 * contact MbientLab Inc, at www.mbientlab.com.
 */

#import "DeviceDetailViewController.h"
#import "MBProgressHUD.h"
#import "APLGraphView.h"

@interface DeviceDetailViewController ()

@property (weak, nonatomic) IBOutlet UILabel *uvLabel;
@property (strong, nonatomic) MBLEvent *uvEvent;
@property (strong, nonatomic) MBLEvent *uvStreamEvent;
@property (strong, nonatomic) MBLEvent *uvBurnEvent;
@property (strong, nonatomic) IBOutlet F3BarGauge *verticalBar;
@property (nonatomic) int settingThreshold;
@property (strong, nonatomic) IBOutlet UISegmentedControl * segmentedControl;
@end

@implementation DeviceDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    //[self.device addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
    [self connectDevice:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self disconnectUVSensor];
    NSLog(@"de-program the board");
    [self connectDevice:NO];
    //[self.device removeObserver:self forKeyPath:@"state"];

}

/*- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (self.device.state == CBPeripheralStateDisconnected) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            //[self setConnected:NO];
            //[self.scrollView scrollRectToVisible:CGRectMake(0, 0, 10, 10) animated:YES];
        }];
    }
}*/

- (void)connectDevice:(BOOL)on
{
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    if (on) {
        hud.labelText = @"Connecting...";
        [self.device connectWithHandler:^(NSError *error) {
            if ([error.domain isEqualToString:kMBLErrorDomain] && error.code == kMBLErrorOutdatedFirmware) {
                [hud hide:YES];
                return;
            }
            hud.mode = MBProgressHUDModeText;
            if (error) {
                hud.labelText = error.localizedDescription;
                [hud hide:YES afterDelay:2];
            } else {
                hud.labelText = @"Connected!";
                [hud hide:YES afterDelay:0.5];
            }
        }];
    } else {
        hud.labelText = @"Disconnecting...";
        [self.device disconnectWithHandler:^(NSError *error) {
            hud.mode = MBProgressHUDModeText;
            if (error) {
                hud.labelText = error.localizedDescription;
                [hud hide:YES afterDelay:2];
            } else {
                hud.labelText = @"Disconnected!";
                [hud hide:YES afterDelay:0.5];
            }
        }];
    }
}

- (IBAction)resetDevice:(id)sender
{
    NSLog(@"Reset device");
    [self.device resetDevice];
    [[self navigationController] popViewControllerAnimated:YES];
}

-(void)programUVSensor
{
    // hooked up to analog input of uv sensor
    MBLGPIOPin *pin0 = self.device.gpio.pins[0];
    
    // hooked up to ground connection of uv sensor
    MBLGPIOPin *pin1 = self.device.gpio.pins[1];
    
    // clear pin to ground
    [pin1 setToDigitalValue:NO];
    
    // event to read every analog pin every 1000 milli seconds
    self.uvStreamEvent = [pin0.analogAbsolute periodicReadWithPeriod:1000];
    
    // event to command board to react upon the threshold detection by flashing led
    //self.uvEvent = [self.uvStreamEvent changeOfEventAcrossThreshold:100 hysteresis:10 output:MBLThresholdValueOutputAbsolute]; //event to look for a threshold about 100mV
    //[self.uvEvent programCommandsToRunOnEvent:^{
        //[self.device.led flashLEDColor:[UIColor redColor] withIntensity:1.0 numberOfFlashes:3];
    //}];
    
    // event to set notifications on the analog period reads and send them to the app (ble notification of analog data)
    [self.uvStreamEvent startNotificationsWithHandler:^(MBLNumericData *obj, NSError *error) {
        _verticalBar.value = (obj.value.floatValue);
        float uvIndex = obj.value.floatValue*100;
        [self.uvLabel setText:[NSString stringWithFormat:@"%.2f", uvIndex]];
        NSLog(@"milli value of uv sensor %f",obj.value.floatValue);
    }];
    
    // event that sums the analog value and stores it
    MBLFilter *uvCountFilter = [self.uvStreamEvent summationOfEvent];
    
    // threshold logic from user input
    int thresh;
    if (self.settingThreshold == 0) {
        thresh = 10000;
    } else {
        thresh = 20000;
    }
    
    // event that detects a threshold on the summed data and notifies the phone when reached and then resets the counter
    self.uvBurnEvent = [uvCountFilter changeOfEventAcrossThreshold:thresh hysteresis:10 output:MBLThresholdValueOutputAbsolute];
    [self.uvBurnEvent startNotificationsWithHandler:^(MBLNumericData *obj, NSError *error) {
        NSLog(@"You are burning, I will let you know you need to flip with a gentle buzz that you should reapply sunscreen or get out of the sun");
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.labelText = @"Re-apply Sunscreen!";
        [hud hide:YES afterDelay:1.0];
        [self.device.hapticBuzzer startHapticWithDutyCycle:255 pulseWidth:500 completion:nil];
        [uvCountFilter reset];
    }];
}

-(void)disconnectUVSensor
{
    // disconnect ground connection of uv sensor by floating it
    MBLGPIOPin *pin1 = self.device.gpio.pins[1];
    pin1.configuration = MBLPinConfigurationNopull;
    
    // remove events, filters, and commands
    [self.uvBurnEvent stopNotifications];
    [self.uvEvent eraseCommandsToRunOnEvent];
    [self.uvStreamEvent stopNotifications];
}

- (IBAction)UpdateUVSetup:(id)sender {
    if(self.segmentedControl.selectedSegmentIndex == 0) {
        self.settingThreshold = 0;
    } else {
        self.settingThreshold = 1;
    }
}
 
- (IBAction)EndEvent:(id)sender {
    [self disconnectUVSensor];
}

- (IBAction)StartEvent:(id)sender {
    [self programUVSensor];
}

/*- (IBAction)turnOnGreenLEDPressed:(id)sender
 {
 [self.device.led setLEDColor:[UIColor greenColor] withIntensity:0.25];
 }
 - (IBAction)flashGreenLEDPressed:(id)sender
 {
 [self.device.led flashLEDColor:[UIColor greenColor] withIntensity:0.25];
 }
 - (IBAction)turnOffLEDPressed:(id)sender
 {
 [self.device.led setLEDOn:NO withOptions:1];
 }*/

@end
