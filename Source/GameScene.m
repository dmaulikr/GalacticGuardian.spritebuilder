//
//  GameScene.m
//  Galactic Guardian
//
//  Created by Scott Lembcke
//  Copyright (c) 2014 Apportable. All rights reserved.
//

//#import "OALSimpleAudio.h"
#import "NebulaBackground.h"

#import "GameScene.h"

#import "Constants.h"
#import "PlayerShip.h"
#import "EnemyShip.h"
#import "Bullet.h"
#import "Controls.h"


@implementation GameScene
{
	CCNode *_scrollNode;
	float _clampWidth, _clampHeight;
	
	CCPhysicsNode *_physics;
	NebulaBackground *_background;
	
	Controls *_controls;
	PlayerShip *_playerShip;
	
	CCTime _fixedTime;
	
	NSMutableArray *_enemies;
	NSMutableArray *_bullets;
	
	int _enemies_killed;
	// Consider extracting when we write more weapon types
	bool _has_auto_firing_weapon;
//	bool _firing;
}

-(instancetype)initWithShipType:(NSString *)shipType
{
	if((self = [super init])){
		
		_has_auto_firing_weapon = true;
		
		CGSize viewSize = [CCDirector sharedDirector].viewSize;
		
		[self setupControls];
		
		_scrollNode = [CCNode node];
		_scrollNode.contentSize = CGSizeMake(1.0, 1.0);
		_scrollNode.position = ccp(viewSize.width/2.0, viewSize.height/2.0);
		[self addChild:_scrollNode z:Z_SCROLL_NODE];
		
		_clampWidth = (GameSceneSize.width - viewSize.width)/2.0;
		_clampHeight = (GameSceneSize.height - viewSize.height)/2.0;
		
		_background = [NebulaBackground node];
		_background.contentSize = GameSceneSize;
		[_scrollNode addChild:_background z:Z_NEBULA];
		
		_physics = [CCPhysicsNode node];
		[_scrollNode addChild:_physics z:Z_PHYSICS];
		
		_physics.iterations = 1;
		
		// Use the gamescene as the collision delegate.
		// See the ccPhysicsCollision* methods below.
		_physics.collisionDelegate = self;
		
		// Enable to show debug outlines for Physics shapes.
//		_physics.debugDraw = YES;
		
		CCNode *bounds = [CCNode node];
		CGFloat boundsWidth = 50.0;
		CGRect boundsRect = CGRectMake(-boundsWidth, -boundsWidth, GameSceneSize.width + 2.0*boundsWidth, GameSceneSize.height + 2.0*boundsWidth);
		bounds.physicsBody = [CCPhysicsBody bodyWithPolylineFromRect:boundsRect cornerRadius:boundsWidth];
		bounds.physicsBody.collisionCategories = @[CollisionCategoryBarrier];
		bounds.physicsBody.collisionMask = @[CollisionCategoryPlayer];
		bounds.physicsBody.elasticity = 1.0;
		[_physics addChild:bounds];
		
		_enemies = [NSMutableArray array];
		_bullets = [NSMutableArray array];
		
		// Add a ship in the middle of the screen.
		_playerShip = (PlayerShip *)[CCBReader load:shipType];
		_playerShip.position = ccp(GameSceneSize.width/2.0, GameSceneSize.height/2.0);
		[_physics addChild:_playerShip z:Z_PLAYER];
		[_background.distortionNode addChild:_playerShip.shieldDistortionSprite];
		
		// Center on the player.
		self.scrollPosition = _playerShip.position;
		
		[self scheduleBlock:^(CCTimer *timer) {
			EnemyShip *enemy = (EnemyShip *)[CCBReader load:@"BadGuy1"];
			if(CCRANDOM_0_1() > 0.33f){
				// left or right sides.
				enemy.position = ccp(CCRANDOM_0_1() > 0.5f ? -64.0f : GameSceneSize.width + 64.0f, CCRANDOM_MINUS1_1() * 400.0f + GameSceneSize.height / 2.0f);
			}else{
				// Top:
				enemy.position = ccp(CCRANDOM_MINUS1_1() * 400.0f + GameSceneSize.width / 2.0f, GameSceneSize.height + 64.0f);
			}

			[_physics addChild:enemy z:Z_ENEMY];
			[_enemies addObject:enemy];
			
			[timer repeatOnceWithInterval:1.5f];
		} delay:1.0f];
		
		for(int i = 0; i < 20; i++){
			// maybe this spoke/circle pattern will be cool.
			float angle = (M_PI * 2.0f / 20.0f) * i;
			[self addWallAt: ccpAdd(ccpMult(ccpForAngle(angle), 150.0f + 250.0f * CCRANDOM_0_1() ), ccp(512, 512))];
		}
		
		// Enable touch events.
		// The entire scene is used as a shoot button.
		self.userInteractionEnabled = YES;
	}
	
	return self;
}

-(void)setupControls
{
	_controls = [Controls node];
	[self addChild:_controls z:Z_CONTROLS];
	
	// TODO should change to __weak once we get rid of the ivar access below.
	__unsafe_unretained typeof(self) _self = self;
	
	[_controls setHandler:^(BOOL value){
		if(value && !_self->_has_auto_firing_weapon) [_self fireBullet];
	} forButton:ControlFireButton];
	
	[_controls setHandler:^(BOOL state) {
		CCDirector *director = [CCDirector sharedDirector];
		CGSize viewSize = director.viewSize;
		
		CCScene *pause = (CCScene *)[CCBReader load:@"PauseScene"];
		
		CCRenderTexture *rt = [CCRenderTexture renderTextureWithWidth:viewSize.width height:viewSize.height];
		rt.contentScale /= 4.0;
		rt.texture.antialiased = YES;
		
		GLKMatrix4 projection = director.projectionMatrix;
		CCRenderer *renderer = [rt begin];
			[_self visit:renderer parentTransform:&projection];
		[rt end];
		
		CCSprite *screenGrab = [CCSprite spriteWithTexture:rt.texture];
		screenGrab.anchorPoint = ccp(0.0, 0.0);
		screenGrab.effect = [CCEffectStack effects:
			[CCEffectBlur effectWithBlurRadius:4.0],
			[CCEffectSaturation effectWithSaturation:-0.5],
			nil
		];
		[pause addChild:screenGrab z:-1];
		
		[director pushScene:pause withTransition:[CCTransition transitionCrossFadeWithDuration:0.25]];
	} forButton:ControlPauseButton];
}

-(void)addWallAt:(CGPoint) pos
{
	CCNode *wall = (CCNode *)[CCBReader load:@"Asteroid"];
	wall.position = pos;
	wall.rotation = CCRANDOM_0_1() * 360.0f;
	[_physics addChild:wall z:Z_ENEMY];
}

-(void)fixedUpdate:(CCTime)delta
{
	_fixedTime += delta;
	
	// Fly the ship using the joystick controls.
	[_playerShip fixedUpdate:delta withInput:_controls.directionValue];
	
	if([_controls getButton:ControlFireButton] && _has_auto_firing_weapon){
		if(_playerShip.lastFireTime + (1.0f / _playerShip.fireRate) < _fixedTime){
			[self fireBullet];
		}
	}

	
	for (EnemyShip *e in _enemies) {
		[e fixedUpdate:delta towardsPlayer:_playerShip];
	}
}

-(void)setScrollPosition:(CGPoint)scrollPosition
{
	float smoothing = 1e3;
	
	CGPoint exp = CGPointMake(
		(scrollPosition.x - GameSceneSize.width/2.0)/_clampWidth,
		(scrollPosition.y - GameSceneSize.height/2.0)/_clampHeight
	);
	
	CGPoint offset = CGPointMake(
		 _clampWidth*(log(pow(smoothing, -exp.x - 1.0) + 1.01) - log(pow(smoothing, exp.x - 1.0) + 1.01)),
		_clampHeight*(log(pow(smoothing, -exp.y - 1.0) + 1.01) - log(pow(smoothing, exp.y - 1.0) + 1.01))
	);
	
	_scrollNode.anchorPoint = ccpAdd(scrollPosition, ccpMult(offset, 1.0/log(smoothing)));
}

-(void)update:(CCTime)delta
{
	self.scrollPosition = _playerShip.position;
}


-(void)enemyDeath:(EnemyShip *)enemy
{
	[enemy removeFromParent];
	[_enemies removeObject:enemy];
	_enemies_killed += 1;
	
	CGPoint pos = enemy.position;
	
	CCNode *debris = [CCBReader load:enemy.debris];
	debris.position = pos;
	debris.rotation = enemy.rotation;
	
	CCColor *weaponColor = [CCColor colorWithRed:0.3f green:0.8f blue:1.0f];
	
	InitDebris(debris, debris, enemy.physicsBody.velocity, weaponColor);
	[_physics addChild:debris z:Z_DEBRIS];
	
	CCNode *explosion = [CCBReader load:@"Particles/ShipExplosion"];
	explosion.position = pos;
	[_physics addChild:explosion z:Z_PARTICLES];
	
	CCNode *distortion = [CCBReader load:@"DistortionParticles/SmallRing"];
	distortion.position = pos;
	[_background.distortionNode addChild:distortion];
	
	[self scheduleBlock:^(CCTimer *timer) {
		[debris removeFromParent];
		[explosion removeFromParent];
		[distortion removeFromParent];
	} delay:5];
}



-(void)destroyBullet:(Bullet *)bullet
{
	[bullet removeFromParent];
	[_bullets removeObject:bullet];
	
	float duration = 0.15;
	CGPoint pos = bullet.position;
	
	// Draw a little flash at it's last position
	CCSprite *flash = [CCSprite spriteWithImageNamed:@"Sprites/Bullets/laserBlue08.png"];
	flash.position = pos;
	[_physics addChild:flash z:Z_FLASH];
	
	[flash runAction:[CCActionSequence actions:
		[CCActionSpawn actions:
			[CCActionFadeOut actionWithDuration:duration],
			[CCActionScaleTo actionWithDuration:duration scale:0.25],
			nil
		],
		[CCActionRemove action],
		nil
	]];
	
	// Draw a little distortion too
	CCSprite *distortion = [CCSprite spriteWithImageNamed:@"DistortionTexture.png"];
	distortion.position = pos;
	distortion.scale = 0.25;
	[_background.distortionNode addChild:distortion];
	
	[distortion runAction:[CCActionSequence actions:
		[CCActionSpawn actions:
			[CCActionFadeOut actionWithDuration:duration],
			[CCActionScaleTo actionWithDuration:duration scale:1.0],
			nil
		],
		[CCActionRemove action],
		nil
	]];
	
	// Make some noise. Add a little chromatically tuned pitch bending to make it more musical.
//	int half_steps = (arc4random()%(2*4 + 1) - 4);
//	float pitch = pow(2.0f, half_steps/12.0f);
//	[[OALSimpleAudio sharedInstance] playEffect:@"Fizzle.wav" volume:1.0 pitch:pitch pan:0.0 loop:NO];
}

-(void)fireBullet
{
	// Don't fire bullets if the ship is destroyed.
	if([_playerShip isDead]) return;
	_playerShip.lastFireTime = _fixedTime;
	
	// This is sort of a fancy math way to figure out where to fire the bullet from.
	// You could figure this out with more code, but I wanted to have fun with some maths.
	// This gets the transform of one of the "gunports" that I marked in the CCB file with a special node.
	CGAffineTransform transform = _playerShip.gunPortTransform;
	
	// An affine transform looks like this when written as a matrix:
	// | a, c, tx |
	// | b, d, ty |
	// The first column, (a, b), is the direction the new x-axis will point in.
	// The second column, (c, d), is the direction the new y-axis will point in.
	// The last column, (tx, ty), is the location of the origin of the new transform.
	
	// The position of the gunport is just the matrix's origin point (tx, ty).
	CGPoint position = ccp(transform.tx, transform.ty);

	// The transform's x-axis, (c, d), will point in the direction of the gunport.
	CGPoint direction = ccp(transform.d, -transform.c);
	
	// So by "fancy math" I really just meant knowing what the numbers in a CGAffineTransform are. ;)
	// When I make my own art, I like to align things on the positive x-axis to make the code "prettier".
	
	// Now we can create the bullet with the position and direction.
	Bullet *bullet = (Bullet *)[CCBReader load:@"Bullet"];
	bullet.position = position;
	bullet.rotation = -CC_RADIANS_TO_DEGREES(ccpToAngle(direction)) + 90.0f;
	
	// Make the bullet move in the direction it's pointed.
	bullet.physicsBody.velocity = ccpMult(direction, bullet.speed);
	
	[_physics addChild:bullet z:Z_BULLET];
	[_bullets addObject:bullet];
	
	// Give the bullet a finite lifetime.
	[bullet scheduleBlock:^(CCTimer *timer){
		[self destroyBullet:bullet];
	} delay:bullet.duration];
	
	// Make some noise. Add a little chromatically tuned pitch bending to make it more musical.
//	int half_steps = (arc4random()%(2*4 + 1) - 4);
//	float pitch = pow(2.0f, half_steps/12.0f);
//	[[OALSimpleAudio sharedInstance] playEffect:@"Laser.wav" volume:1.0 pitch:pitch pan:0.0 loop:NO];
}

// Recursive helper function to set up physics on the debris child nodes.
static void
InitDebris(CCNode *root, CCNode *node, CGPoint velocity, CCColor *burnColor)
{
	// If the node has a body, set some properties.
	CCPhysicsBody *body = node.physicsBody;
	body.collisionCategories = @[CollisionCategoryDebris];
	
	if(body){
		// Bodies with the same group reference don't collide.
		// Any type of object will do. It's the object reference that is important.
		// In this case, I want the debris to collide with everything except other debris from the same ship.
		// I'll use a reference to the root node since that is unique for each explosion.
		body.collisionGroup = root;
		
		// Copy the velocity onto the body + a little random.
		body.velocity = ccpAdd(velocity, ccpMult(CCRANDOM_IN_UNIT_CIRCLE(), 150.0));
		body.angularVelocity = 5.0*CCRANDOM_MINUS1_1();
		
		// Nodes with bodies should also be sprites.
		// This is a convenient place to add the fade action.
		node.color = burnColor;
		[node runAction: [CCActionSequence actions:
		 [CCActionDelay actionWithDuration:0.5],
		 [CCActionFadeOut actionWithDuration:2.0], nil]];
	}
	
	// Recurse on the children.
	for(CCNode *child in node.children) InitDebris(root, child, velocity, burnColor);
}

-(void)playerDestroyed;
{
	
	//The ship was destroyed!
	[_playerShip removeFromParent];
	[_playerShip.shieldDistortionSprite removeFromParent];
	
	CGPoint pos = _playerShip.position;
	
	CCNode *debris = [CCBReader load:_playerShip.debris];
	debris.position = pos;
	debris.rotation = _playerShip.rotation;
	InitDebris(debris, debris, _playerShip.physicsBody.velocity, [CCColor colorWithRed:1.0f green:1.0f blue:0.3f]);
	[_physics addChild:debris z:Z_DEBRIS];
	
	CCNode *explosion = [CCBReader load:@"Particles/ShipExplosion"];
	explosion.position = pos;
	[_physics addChild:explosion z:Z_PARTICLES];
	
	CCNode *distortion = [CCBReader load:@"DistortionParticles/LargeRing"];
	distortion.position = pos;
	[_background.distortionNode addChild:distortion];
	
	[self scheduleBlock:^(CCTimer *timer) {
		[debris removeFromParent];
		[explosion removeFromParent];
		[distortion removeFromParent];
	} delay:5];
	
	[self scheduleBlock:^(CCTimer *timer){
		// Go back to the menu after a short delay.
		[[CCDirector sharedDirector] replaceScene:[CCBReader loadAsScene:@"MainMenu"]];
	} delay:5.0];
	

	for (EnemyShip * e in _enemies) {
		// explode based on distance from player.
		float dist = ccpLength(ccpSub(_playerShip.position, e.position));
		[e scheduleBlock:^(CCTimer *timer) {
			[self enemyDeath:e];
		} delay:dist / 200.0f];
	}
}

#pragma mark - CCPhysicsCollisionDelegate methods


-(BOOL)ccPhysicsCollisionBegin:(CCPhysicsCollisionPair *)pair ship:(PlayerShip *)player enemy:(EnemyShip *)enemy
{
	if([_playerShip takeDamage]){
		[self playerDestroyed];
		// Don't process the collision so the enemy spaceship will survive and mock you.
		return NO;
	}else{
		// Player took damage, the enemy should self destruct.
		[self enemyDeath: enemy];
		return YES;
	}
	
	
}

-(BOOL)ccPhysicsCollisionBegin:(CCPhysicsCollisionPair *)pair bullet:(Bullet *)bullet enemy:(EnemyShip *)enemy
{
	[self destroyBullet:bullet];
	
	if([enemy takeDamage]){
		[self enemyDeath:enemy];
	}
	
	return NO;
}

-(BOOL)ccPhysicsCollisionBegin:(CCPhysicsCollisionPair *)pair bullet:(Bullet *)bullet wall:(CCNode *)wall
{
	[self destroyBullet:bullet];
	return NO;
}


@end
