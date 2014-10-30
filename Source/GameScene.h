@class PlayerShip, EnemyShip, Bullet;

@interface GameScene : CCScene<CCPhysicsCollisionDelegate>

-(instancetype)initWithShipType:(NSString *)shipType level:(int) shipLevel;

// TODO should extract this to the enemy class
-(void)enemyDeath:(EnemyShip *)enemy;

-(void)drawFlash:(CGPoint) position withImage:(NSString*) imagePath;
-(void)drawBulletFlash:(Bullet *)fromBullet;

@property(nonatomic, readonly) CCNode *distortionNode;

@property(nonatomic, readonly) PlayerShip *player;
@property(nonatomic, readonly) CGPoint playerPosition;

@property(nonatomic, readonly) NSMutableArray *enemies;

@end

// Recursive helper function to set up physics on the debris child nodes.
void InitDebris(CCNode *root, CCNode *node, CGPoint velocity, CCColor *burnColor);
